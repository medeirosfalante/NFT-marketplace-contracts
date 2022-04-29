const ArtMarketplace = artifacts.require("Marketplace");

const NFT = artifacts.require("NFT");


module.exports = async function(deployer) {

  await deployer.deploy(ArtMarketplace)
  const market = await ArtMarketplace.deployed()
  const instance = await deployer.deploy(NFT, "Non Fungable Tokens", "NFT");
};