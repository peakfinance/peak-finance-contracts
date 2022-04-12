require("dotenv").config()
const RPC_URL = process.env.METIS_URL
const PRIVATE_KEY = process.env.METIS_PRIVATE_KEY
const PUBLIC_KEY = process.env.METIS_PUBLIC_KEY
const CONTRACT_ADDRESS = "0x9DFf893BBCE5E1aFe42FffcB4cbceFcF644330ff"
const { createAlchemyWeb3 } = require("@alch/alchemy-web3")
const web3 = createAlchemyWeb3(RPC_URL)
const contract = require("../artifacts/contracts/PBond.sol/PBond.json")
const contractObject = new web3.eth.Contract(contract.abi, CONTRACT_ADDRESS)
async function processTranscation(data) {
    const nonce = await web3.eth.getTransactionCount(PUBLIC_KEY, "latest") //get latest nonce
    const tx = {
        from: PUBLIC_KEY,
        to: CONTRACT_ADDRESS,
        nonce: nonce,
        gas: 5000000,
        data: data,
      }
    const signedTx = await web3.eth.accounts.signTransaction(tx, PRIVATE_KEY)
    try {
        await web3.eth.sendSignedTransaction(
          signedTx.rawTransaction,
          function (err, hash) {
            if (!err) {
              console.log("The hash of your transaction is: ", hash);       
            } else {
              console.log("Something went wrong when submitting your transaction:", err);
            }
          }
        )
      }
      catch(err) {
        console.log("Something went wrong when submitting your transaction:", err);
      }
}

async function main() {

    await processTranscation(contractObject.methods.mint("0xe6C2D1D7f6EE9E4eE9F8B865D9b5931C06C9c7d1", "10000000000000000000").encodeABI());
    
    console.log("Processed The Transaction");
}

main();