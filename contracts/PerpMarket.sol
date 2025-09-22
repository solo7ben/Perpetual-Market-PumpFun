// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "./interfaces/IERC20.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {FlywheelTreasury} from "./FlywheelTreasury.sol";

contract PerpMarket {
    struct Market {
        address asset;
        IOracle oracle;
        bool listed;
        uint16 feeBps;
        uint16 liqFeeBps;
    }

    struct Position {
        bool isLong;
        bool open;
        uint256 sizeUsd;
        uint256 entryPrice;
        uint256 collateral;
    }

    IERC20 public immutable pumpToken;
    FlywheelTreasury public immutable flywheel;

    uint256 public constant USD_DECIMALS = 1e18;
    uint256 public constant MAX_LEVERAGE_X = 10 * 1e18;
    uint256 public constant IM_BPS = 1000;
    uint256 public constant MM_BPS = 625;
    uint256 public constant BPS_DENOM = 10_000;

    mapping(address => Market) public markets;
    mapping(address => mapping(address => Position)) public positions;

    mapping(address => int256) public realizedPnlUsd;
    address[] public traders;
    mapping(address => bool) private seenTrader;

    event MarketListed(address indexed asset, address indexed oracle, uint16 feeBps, uint16 liqFeeBps);
    event PositionOpened(address indexed trader, address indexed asset, bool isLong, uint256 sizeUsd, uint256 collateral, uint256 entryPrice);
    event PositionIncreased(address indexed trader, address indexed asset, uint256 addSizeUsd, uint256 addCollateral, uint256 newEntryPrice);
    event PositionClosed(address indexed trader, address indexed asset, uint256 sizeUsd, int256 pnlUsd, uint256 fees);
    event Liquidated(address indexed trader, address indexed asset, uint256 sizeUsd, int256 pnlUsd, uint256 penalty);

    constructor(IERC20 _pumpToken) {
        pumpToken = _pumpToken;
        flywheel = new FlywheelTreasury(_pumpToken, address(this));
    }

    function listMarket(address asset, address oracle, uint16 feeBps, uint16 liqFeeBps) external {
        require(!markets[asset].listed, "Already listed");
        require(feeBps < 200, "Fee too high");
        require(liqFeeBps <= 500, "Liq fee too high");
        require(asset != address(0) && oracle != address(0), "Zero addr");

        IOracle o = IOracle(oracle);
        int256 p = o.latestAnswer();
        require(p > 0, "Bad oracle");

        markets[asset] = Market({asset: asset, oracle: o, listed: true, feeBps: feeBps, liqFeeBps: liqFeeBps});
        emit MarketListed(asset, oracle, feeBps, liqFeeBps);
    }

    function _price(address asset) internal view returns (uint256) {
        require(markets[asset].listed, "Unlisted");
        uint256 px = uint256(markets[asset].oracle.latestAnswer());
        require(px > 0, "Oracle error");
        return px;
    }

    function _collateralToUsd(uint256 amt, uint8 pumpDecimals, uint256 px1e8) internal pure returns (uint256) {
        return (amt * (10 ** (26 - pumpDecimals)) * px1e8) / 1e8;
    }

    function _takeFee(uint256 notionalUsd, address asset) internal returns (uint256 feePump) {
        Market memory m = markets[asset];
        uint256 feeUsd = (notionalUsd * m.feeBps) / BPS_DENOM;
        uint8 pdec = pumpToken.decimals();
        uint256 px = _price(asset);
        feePump = (feeUsd * (10 ** pdec) * 1e8) / px;
        require(pumpToken.transfer(address(flywheel), feePump), "fee xfer");
        flywheel.recycle(feePump);
    }

    function openPosition(address asset, bool isLong, uint256 collateralPump, uint256 leverageX) external {
        require(markets[asset].listed, "Unlisted");
        require(leverageX > 1e18 && leverageX <= MAX_LEVERAGE_X, "Bad leverage");
        require(collateralPump > 0, "No collateral");

        require(pumpToken.transferFrom(msg.sender, address(this), collateralPump), "coll xfer");

        Position storage pos = positions[asset][msg.sender];
        uint256 px = _price(asset);
        uint8 pdec = pumpToken.decimals();

        uint256 sizeUsd = (collateralPump * leverageX * (10 ** (18 - pdec)) * px) / 1e8 / 1e18;
        uint256 collUsd = _collateralToUsd(collateralPump, pdec, px);
        require(collUsd * BPS_DENOM >= sizeUsd * IM_BPS, "IM violated");

        uint256 feePump = _takeFee(sizeUsd, asset);

        if (!pos.open) {
            pos.isLong = isLong;
            pos.open = true;
            pos.sizeUsd = sizeUsd;
            pos.entryPrice = px;
            pos.collateral = collateralPump - feePump;
            if (!seenTrader[msg.sender]) {
                seenTrader[msg.sender] = true;
                traders.push(msg.sender);
            }
            emit PositionOpened(msg.sender, asset, isLong, sizeUsd, pos.collateral, px);
        } else {
            require(pos.isLong == isLong, "Flip not allowed");
            uint256 newSize = pos.sizeUsd + sizeUsd;
            uint256 newEntry = (pos.entryPrice * pos.sizeUsd + px * sizeUsd) / newSize;
            pos.sizeUsd = newSize;
            pos.entryPrice = newEntry;
            pos.collateral += (collateralPump - feePump);
            emit PositionIncreased(msg.sender, asset, sizeUsd, collateralPump - feePump, newEntry);
        }

        require(_isSolvent(pos, px), "Post-open solvency");
    }

    function closePosition(address asset, uint256 reduceUsd) external {
        Position storage pos = positions[asset][msg.sender];
        require(pos.open, "No position");
        require(reduceUsd > 0 && reduceUsd <= pos.sizeUsd, "Bad size");

        uint256 px = _price(asset);
        (int256 pnlUsd,) = _pnlUsd(pos, px);
        int256 realize = (pnlUsd * int256(reduceUsd)) / int256(pos.sizeUsd);

        uint256 feePump = _takeFee(reduceUsd, asset);

        pos.sizeUsd -= reduceUsd;
        if (pos.sizeUsd == 0) {
            pos.open = false;
        }

        uint8 pdec = pumpToken.decimals();
        int256 pumpDelta = _usdToPump(realize, pdec, px);
        if (pumpDelta >= 0) {
            pos.collateral += uint256(pumpDelta);
        } else {
            uint256 absDelta = uint256(-pumpDelta);
            require(pos.collateral >= absDelta, "Neg collateral");
            pos.collateral -= absDelta;
        }

        require(pos.collateral >= feePump, "Fee exceeds collateral");
        pos.collateral -= feePump;

        uint256 withdrawPump = pos.collateral;
        if (pos.open) {
            withdrawPump = (pos.collateral * reduceUsd) / (pos.sizeUsd + reduceUsd);
            pos.collateral -= withdrawPump;
        }
        require(pumpToken.transfer(msg.sender, withdrawPump), "withdraw xfer");

        realizedPnlUsd[msg.sender] += realize;

        emit PositionClosed(msg.sender, asset, reduceUsd, realize, feePump);
        if (pos.open) require(_isSolvent(pos, px), "Post-close solvency");
    }

    function addCollateral(address asset, uint256 pumpAmount) external {
        Position storage pos = positions[asset][msg.sender];
        require(pos.open, "No position");
        require(pumpToken.transferFrom(msg.sender, address(this), pumpAmount), "xfer fail");
        pos.collateral += pumpAmount;
        require(_isSolvent(pos, _price(asset)), "Not solvent");
    }

    function liquidate(address asset, address trader) external {
        Position storage pos = positions[asset][trader];
        require(pos.open, "No position");
        uint256 px = _price(asset);
        require(!_isSolventMM(pos, px), "Healthy");

        (int256 pnlUsd, uint256 absNotional) = _pnlUsd(pos, px);

        uint256 penaltyPump = _penaltyPump(absNotional, markets[asset].liqFeeBps, pumpToken.decimals(), px);
        if (penaltyPump > pos.collateral) penaltyPump = pos.collateral;
        require(pumpToken.transfer(address(flywheel), penaltyPump), "penalty xfer");
        flywheel.recycle(penaltyPump);

        uint8 pdec = pumpToken.decimals();
        int256 pumpDelta = _usdToPump(pnlUsd, pdec, px);
        uint256 coll = pos.collateral;
        if (pumpDelta >= 0) {
            coll = coll + uint256(pumpDelta);
        } else {
            uint256 lossPump = uint256(-pumpDelta);
            coll = coll > lossPump ? coll - lossPump : 0;
        }
        coll = coll > penaltyPump ? coll - penaltyPump : 0;

        pos.open = false;
        pos.sizeUsd = 0;
        pos.collateral = 0;

        if (coll > 0) {
            require(pumpToken.transfer(trader, coll), "refund xfer");
        }

        realizedPnlUsd[trader] += pnlUsd;

        emit Liquidated(trader, asset, absNotional, pnlUsd, penaltyPump);
    }

    function pnlUsd(address asset, address trader) external view returns (int256 pnl, uint256 notional) {
        Position memory p = positions[asset][trader];
        if (!p.open) return (0, 0);
        return _pnlUsd(p, _price(asset));
    }

    function getTopTraders(uint256 k) external view returns (address[] memory addrs, int256[] memory pnls) {
        uint256 n = traders.length;
        if (k > n) k = n;
        address[] memory A = new address[](n);
        int256[] memory P = new int256[](n);
        for (uint256 i = 0; i < n; i++) {
            A[i] = traders[i];
            P[i] = realizedPnlUsd[traders[i]];
        }
        for (uint256 i = 0; i < k; i++) {
            uint256 maxIdx = i;
            for (uint256 j = i + 1; j < n; j++) {
                if (P[j] > P[maxIdx]) maxIdx = j;
            }
            (P[i], P[maxIdx]) = (P[maxIdx], P[i]);
            (A[i], A[maxIdx]) = (A[maxIdx], A[i]);
        }
        addrs = new address[](k);
        pnls = new int256[](k);
        for (uint256 i = 0; i < k; i++) {
            addrs[i] = A[i];
            pnls[i] = P[i];
        }
    }

    function flywheelAddress() external view returns (address) {
        return address(flywheel);
    }

    function tradersCount() external view returns (uint256) {
        return traders.length;
    }

    function _pnlUsd(Position memory p, uint256 px) internal pure returns (int256 pnl, uint256 notional) {
        notional = p.sizeUsd;
        if (px == p.entryPrice) return (0, notional);
        if (p.isLong) {
            int256 num = int256(px) - int256(p.entryPrice);
            pnl = (int256(p.sizeUsd) * num) / int256(p.entryPrice);
        } else {
            int256 num = int256(p.entryPrice) - int256(px);
            pnl = (int256(p.sizeUsd) * num) / int256(p.entryPrice);
        }
    }

    function _usdToPump(int256 usd, uint8 pdec, uint256 px1e8) internal pure returns (int256) {
        return (usd * int256(10 ** pdec) * int256(1e8)) / int256(px1e8) / int256(USD_DECIMALS);
    }

    function _penaltyPump(uint256 notionalUsd, uint16 bps, uint8 pdec, uint256 px) internal pure returns (uint256) {
        uint256 penaltyUsd = (notionalUsd * bps) / BPS_DENOM;
        return (penaltyUsd * (10 ** pdec) * 1e8) / px / USD_DECIMALS;
    }

    function _isSolvent(Position memory p, uint256 px) internal view returns (bool) {
        (int256 pnl,) = _pnlUsd(p, px);
        uint8 d = pumpToken.decimals();
        uint256 collUsd = _collateralToUsd(p.collateral, d, px);
        int256 equity = int256(collUsd) + pnl;
        if (equity <= 0) return false;
        return uint256(equity) * BPS_DENOM >= p.sizeUsd * IM_BPS;
    }

    function _isSolventMM(Position memory p, uint256 px) internal view returns (bool) {
        (int256 pnl,) = _pnlUsd(p, px);
        uint8 d = pumpToken.decimals();
        uint256 collUsd = _collateralToUsd(p.collateral, d, px);
        int256 equity = int256(collUsd) + pnl;
        if (equity <= 0) return false;
        return uint256(equity) * BPS_DENOM >= p.sizeUsd * MM_BPS;
    }
}
