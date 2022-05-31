const HDWalletProvider = require('@truffle/hdwallet-provider')
const fs = require('fs')
const mnemonic = fs.readFileSync('.secret').toString().trim()

module.exports = {
  networks: {
    development: {
      host: '127.0.0.1', // Localhost (default: none)
      port: 7545, // Standard BSC port (default: none)
      network_id: '*', // Any network (default: none)
    },
    testnet: {
      provider: () =>
        new HDWalletProvider(
          mnemonic,
          `https://data-seed-prebsc-1-s1.binance.org:8545`,
        ),
      network_id: 97,
      confirmations: 2,
      timeoutBlocks: 2000,
      skipDryRun: true,
      networkCheckTimeout: 1000000,
    },
    bsc: {
      provider: () =>
        new HDWalletProvider(mnemonic, `https://bsc-dataseed1.binance.org`),
      network_id: 56,
      confirmations: 10,
      timeoutBlocks: 200,
      skipDryRun: true,
    },
    coinex_testnet: {
      provider: () =>
        new HDWalletProvider(mnemonic, `https://testnet-rpc.coinex.net`),
      network_id: 53,
      confirmations: 2,
      timeoutBlocks: 2000,
      skipDryRun: true,
      networkCheckTimeout: 1000000,
    },
  },

  // Set default mocha options here, use special reporters etc.
  mocha: {
    // timeout: 100000
  },

  // Configure your compilers
  compilers: {
    solc: {
      version: '0.8.13', // A version or constraint - Ex. "^0.8.0"
      settings: {
        optimizer: {
          enabled: true,
          runs: 2,
        },
        evmVersion: 'byzantium',
      },
    },
  },
}
