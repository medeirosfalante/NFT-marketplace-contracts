const ArtMarketplace = artifacts.require('Marketplace')

const NFT = artifacts.require('NFT')
const Token = artifacts.require('Token')

module.exports = async function (deployer, network, accounts) {
  await deployer.deploy(ArtMarketplace)
  const market = await ArtMarketplace.deployed()
  const instance = await deployer.deploy(NFT, 'Non Fungable Tokens', 'NFT')
  console.log(accounts[0])
  const tokenIntance = await deployer.deploy(Token, 'BRZ', 100000000000, {
    from: accounts[0],
  })
}
