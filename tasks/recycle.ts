import 'dotenv/config'
import { readFileSync } from 'fs'
import { createPublicClient, createWalletClient, http, parseUnits } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import { Address, mainnet } from 'viem/chains'

const cfg = JSON.parse(readFileSync('config/addresses.json', 'utf-8'))
const RPC_URL = process.env.RPC_URL || 'http://127.0.0.1:8545'
const PRIVATE_KEY = (process.env.PRIVATE_KEY || '') as `0x${string}`

const pumpAbi = [
  { type: 'function', name: 'transfer', stateMutability: 'nonpayable', inputs: [{type:'address'},{type:'uint256'}], outputs:[{type:'bool'}] }
]

async function main() {
  const account = privateKeyToAccount(PRIVATE_KEY)
  const pub = createPublicClient({ chain: mainnet, transport: http(RPC_URL) })
  const wallet = createWalletClient({ account, chain: mainnet, transport: http(RPC_URL) })

  const pump: Address = cfg.pumpToken
  const flywheel: Address = cfg.flywheel

  const amt = parseUnits('100', 18)
  await wallet.writeContract({ address: pump, abi: pumpAbi, functionName: 'transfer', args: [flywheel, amt] })
  console.log('recycled:', amt.toString(), 'to', flywheel)
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
