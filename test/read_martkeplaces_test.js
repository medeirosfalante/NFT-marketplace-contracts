const marketplace = artifacts.require('./Marketplace.sol')
const NFT = artifacts.require('NFT')

contract('Marketplace', async (accounts) => {
  let nftRef
  const seller = accounts[0]
  const buyer1 = accounts[1]
  const buyer2 = accounts[2]
  const tokenId = 1234
  const tokenId2 = 3456
  it('create nft', async () => {
    nftRef = await NFT.deployed()
    await nftRef.mint(seller, 'https://game.example/item-id-8u5h2m.json')
    const balance = await nftRef.balanceOf.call(seller);
    assert.equal(balance.valueOf(), 1);
  })
})
