import 'dotenv/config'
import { readFileSync } from 'fs'
import { createPublicClient, http, formatUnits } from 'viem'
import { Address, mainnet } from 'viem/chains'

const cfg = JSON.parse(readFileSync('config/addresses.json', 'utf-8'))
const RPC_URL = process.env.RPC_URL || 'http://127.0.0.1:8545'

const abi = [
  { type: 'function', name: 'tradersCount', stateMutability: 'view', inputs: [], outputs: [{type:'uint256'}]},
  { type: 'function', name: 'traders', stateMutability: 'view', inputs: [{name:'',type:'uint256'}], outputs: [{type:'address'}]},
  { type: 'function', name: 'realizedPnlUsd', stateMutability: 'view', inputs: [{name:'',type:'address'}], outputs: [{type:'int256'}]},
]

async function main() {
  const client = createPublicClient({ chain: mainnet, transport: http(RPC_URL) })
  const market: Address = cfg.perpMarket

  const count = await client.readContract({ address: market, abi, functionName: 'tradersCount' }) as bigint

  const entries: { addr: Address; pnl: bigint }[] = []
  for (let i = 0n; i < count; i++) {
    const addr = await client.readContract({ address: market, abi, functionName: 'traders', args: [i] }) as Address
    const pnl = await client.readContract({ address: market, abi, functionName: 'realizedPnlUsd', args: [addr] }) as bigint
    entries.push({ addr, pnl })
  }

  entries.sort((a, b) => (a.pnl > b.pnl ? -1 : 1))
  console.table(entries.slice(0, 10).map(e => ({
    trader: e.addr,
    realizedPnlUsd: Number(formatUnits(e.pnl, 18)).toFixed(4),
  })))
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
