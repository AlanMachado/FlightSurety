const HDWalletProvider = require('truffle-hdwallet-provider');
const infuraKey = "00f02bb3ed0e4a21b2f79f99eb1fb6ea";
const mnemonic = "angle expire craft private drastic reward marble priority abstract ignore chef note";

module.exports = {
    // Uncommenting the defaults below
    // provides for an easier quick-start with Ganache.
    // You can also follow this format for other networks;
    // see <http://truffleframework.com/docs/advanced/configuration>
    // for more details on how to specify configuration options!
    networks: {
        development: {
            host: "127.0.0.1",
            port: 8545,
            network_id: "*"
        },
        rinkeby: {
            provider: () => new HDWalletProvider(mnemonic, `https://rinkeby.infura.io/v3/${infuraKey}`),
            network_id: 4,
            gas: 6500000,
            gasPrice: 10000000000
        }
    },
    mocha: {
        // timeout: 100000
    },
    compilers: {
        solc: {

        }
    }
    /*
    networks: {
      development: {
        host: "127.0.0.1",
        port: 7545,
        network_id: "*"
      },
      test: {
        host: "127.0.0.1",
        port: 7545,
        network_id: "*"
      }
    }
    */
};