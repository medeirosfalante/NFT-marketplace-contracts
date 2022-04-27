const ArtMarketplace = artifacts.require("Marketplace");

module.exports = async function(deployer) {

await deployer.deploy(ArtMarketplace)

  const market = await ArtMarketplace.deployed()

};