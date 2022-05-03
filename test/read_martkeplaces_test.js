const Marketplace = artifacts.require('./Marketplace.sol')
const NFT = artifacts.require('NFT')

const util = require('../utils/time')

contract('Marketplace', async (accounts) => {
  let nftRef
  const seller = accounts[0]
  const buyer1 = accounts[1]
  const buyer2 = accounts[2]
  const tokenId1 = 0
  const tokenId2 = 1
  it('create nft', async () => {
    nftRef = await NFT.deployed()
    await nftRef.mint(seller, 'https://game.example/item-id-8u5h2m.json', {
      from: seller,
    })
    await nftRef.mint(seller, 'https://game.example/item-id-8u5h2m.json', {
      from: seller,
    })
    const balance = await nftRef.balanceOf.call(seller)
    assert.equal(balance.valueOf(), 2)
  })

  it('create marketplace order', async () => {
    let marketplace = await Marketplace.deployed()
    nftRef = await NFT.deployed()
    await nftRef.approve(marketplace.address, tokenId1)
    await nftRef.approve(marketplace.address, tokenId2)
    var ts = util.addHours(10, new Date())
    const price = web3.utils.toWei('1', 'ether')
    await marketplace.createOrder(nftRef.address, tokenId1, price, ts, {
      from: seller,
    })
    await marketplace.createOrder(nftRef.address, tokenId2, price, ts, {
      from: seller,
    })
  })

  it('lists orders', async () => {
    let marketplace = await Marketplace.deployed()
    const orders = await marketplace.getOrders.call()
    assert.equal(orders.length, 2)
  })
})
