/** @type import('hardhat/config').HardhatUserConfig */
const dotenv = require("dotenv");
dotenv.config({ path: __dirname + "/.env" });

require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("hardhat-gas-reporter");
require("hardhat-contract-sizer");

const DEFAULT_COMPILER_SETTINGS = {
    version: '0.7.6',
    settings: {
        evmVersion: 'istanbul',
        optimizer: {
            enabled: true,
            runs: 1000000,
        },
        metadata: {
            bytecodeHash: 'none',
        },
    },
}

module.exports = {
    defaultNetwork: 'hardhat',
    solidity: {
        compilers: [
            {
                version: "0.8.18",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 1000000,
                    },
                },
            },
            {
                version: "0.6.6",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 1000000,
                    },
                },
            },
            {
                version: '0.7.6',
                settings: {
                    evmVersion: 'istanbul',
                    optimizer: {
                        enabled: true,
                        runs: 1000000,
                    },
                    metadata: {
                        bytecodeHash: 'none',
                    },
                },
            }
        ],
        overrides: {
            '@uniswap/v3-periphery/contracts/base/Multicall.sol': DEFAULT_COMPILER_SETTINGS,
            '@uniswap/v3-periphery/contracts/base/PeripheryImmutableState.sol': DEFAULT_COMPILER_SETTINGS,
            '@uniswap/v3-core/contracts/libraries/TickMath.sol': DEFAULT_COMPILER_SETTINGS,
            '@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol': DEFAULT_COMPILER_SETTINGS
        }
    },
    networks: {
        mainnet: {
            url: process.env.BSC_MAINNET_PROVIDER ?? 'https://bsc-dataseed3.binance.org/',
            accounts: [
                process.env.MAINNET_DEPLOYER ?? '0x0000000000000000000000000000000000000000000000000000000000000001',
            ],
            timeout: 900000,
            chainId: 56
        },
    },
    etherscan: {
        apiKey: process.env.ETHERSCAN_API_KEY,
    },
    contractSizer: {
        alphaSort: true,
        disambiguatePaths: false,
        runOnCompile: true,
        strict: true,
        only: [],
    }
};
