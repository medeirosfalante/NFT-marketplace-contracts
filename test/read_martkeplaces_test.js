const Marketplace = artifacts.require('./Marketplace.sol')
const NFT = artifacts.require('NFT')

const util = require('../utils/time')

contract('Marketplace', async (accounts) => {
  let nftRef
  const seller = accounts[0]
  const buyer1 = accounts[1]
  const buyer2 = accounts[2]
  const tokenId = 0
  it('create nft', async () => {
    nftRef = await NFT.deployed()
    await nftRef.mint(seller, 'https://game.example/item-id-8u5h2m.json', {
      from: seller,
    })
    const balance = await nftRef.balanceOf.call(seller)
    assert.equal(balance.valueOf(), 1)
  })

  it('create marketplace order', async () => {
    let marketplace = await Marketplace.deployed()
    nftRef = await NFT.deployed()
    const ownerOf = await nftRef.ownerOf.call(0)
    await nftRef.approve(marketplace.address, tokenId)
    var ts = util.addHours(10, new Date())
    const price = web3.utils.toWei('1', 'ether')
    await marketplace.createOrder(nftRef.address, tokenId, price, ts, {
      from: seller,
    })
  })
})
