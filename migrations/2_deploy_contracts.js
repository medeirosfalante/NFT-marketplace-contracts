const ArtMarketplace = artifacts.require('Marketplace')

const NFT = artifacts.require('NFT')
const Token = artifacts.require('Token')

module.exports = async function (deployer, network, accounts) {
  await deployer.deploy(ArtMarketplace)
  await ArtMarketplace.deployed()
  const total = web3.utils.toWei('10000', 'ether')
  const accountRef = web3.utils.toWei('100', 'ether')
  await deployer.deploy(NFT, 'Non Fungable Tokens', 'NFT')
  await deployer.deploy(Token, 'BRZ', total.toString(), {
    from: accounts[0],
  })
  const tokenIntance = await Token.deployed()
  tokenIntance.transfer(accounts[2],accountRef.toString())

}
