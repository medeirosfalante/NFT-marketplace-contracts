const Marketplace = artifacts.require('./Marketplace.sol')
const NFT = artifacts.require('NFT')
const Token = artifacts.require('Token')

const util = require('../utils/time')

contract('Marketplace', async (accounts) => {
  let nftRef
  let marketplace
  const seller = accounts[0]
  const seller2 = accounts[1]
  const buyer1 = accounts[2]
  const tokenId1 = 0
  const tokenId2 = 1
  const tokenId3 = 2
  const tokenId4 = 3

  it('add token', async () => {
    marketplace = await Marketplace.deployed()

    let BRz = await Token.deployed()
    await marketplace.AddToken(BRz.address)
    const tokens = await marketplace.listTokens.call({
      from: seller2,
    })
    assert.equal(tokens.length, 1)
  })

  it('create nft seller 1', async () => {
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

  it('create nft seller 2', async () => {
    nftRef = await NFT.deployed()
    await nftRef.mint(seller2, 'https://game.example/item-id-8u5h2m.json', {
      from: seller2,
    })
    await nftRef.mint(seller2, 'https://game.example/item-id-8u5h2m.json', {
      from: seller2,
    })
    const balance = await nftRef.balanceOf.call(seller2)
    assert.equal(balance.valueOf(), 2)
  })

  it('create marketplace order seller 1', async () => {
    let BRz = await Token.deployed()
    nftRef = await NFT.deployed()
    await nftRef.approve(marketplace.address, tokenId1, {
      from: seller,
    })
    await nftRef.approve(marketplace.address, tokenId2, {
      from: seller,
    })
    var ts = util.addHours(10, new Date())
    const price = web3.utils.toWei('1', 'ether')
    await marketplace.createOrder(
      nftRef.address,
      tokenId1,
      price,
      ts,
      BRz.address,
      {
        from: seller,
      },
    )
    await marketplace.createOrder(
      nftRef.address,
      tokenId2,
      price,
      ts,
      BRz.address,
      {
        from: seller,
      },
    )
  })

  it('create marketplace order seller 2', async () => {
    nftRef = await NFT.deployed()
    let BRz = await Token.deployed()
    await nftRef.approve(marketplace.address, tokenId3, {
      from: seller2,
    })
    var ts = util.addHours(10, new Date())
    const price = web3.utils.toWei('1', 'ether')
    await marketplace.createOrder(
      nftRef.address,
      tokenId3,
      price,
      ts,
      BRz.address,
      {
        from: seller2,
      },
    )
  })


  it('lists orders', async () => {
    const orders = await marketplace.getOrders.call()
    assert.equal(orders.length, 3)
  })

  it('lists my orders', async () => {
    let marketplace = await Marketplace.deployed()
    const orders = await marketplace.getMyOrders.call({
      from: seller2,
    })
    assert.equal(orders.length, 1)
  })

  it('non owner add token', async () => {
    let BRz = await Token.deployed()
    try {
      await marketplace.AddToken.call(BRz.address, {
        from: seller2,
      })
    } catch (e) {
      assert.isNotNull(e, 'there was no error')
    }
  })

  it('remove token', async () => {
    let BRz = await Token.deployed()
    await marketplace.removeToken(BRz.address)
    const tokens = await marketplace.listTokens.call({
      from: seller2,
    })
    assert.equal(tokens.length, 0)
  })

  it('create marketplace order seller 1 without token supported', async () => {
    nftRef = await NFT.deployed()
    await nftRef.approve(marketplace.address, tokenId4, {
      from: seller2,
    })
    var ts = util.addHours(10, new Date())
    const price = web3.utils.toWei('1', 'ether')
    try {
      await marketplace.createOrder(
        nftRef.address,
        tokenId4,
        price,
        ts,
        '0x420412e765bfa6d85aaac94b4f7b708c89be2e2b',
        {
          from: seller2,
        },
      )
    } catch (e) {
      assert.isNotNull(e, 'there was no error')
    }
  })

  it('create marketplace order seller 1 without token supported', async () => {
    nftRef = await NFT.deployed()
    await nftRef.approve(marketplace.address, tokenId4, {
      from: seller2,
    })
    var ts = util.addHours(10, new Date())
    const price = web3.utils.toWei('1', 'ether')
    try {
      await marketplace.createOrder(
        nftRef.address,
        tokenId4,
        price,
        ts,
        '0x420412e765bfa6d85aaac94b4f7b708c89be2e2b',
        {
          from: seller2,
        },
      )
    } catch (e) {
      assert.isNotNull(e, 'there was no error')
    }
  })


  it('create buy  1', async () => {
    let BRz = await Token.deployed()
    const price = web3.utils.toWei('1', 'ether')
    nftRef = await NFT.deployed()
    await BRz.approve(marketplace.address, price, {
      from: buyer1,
    })

    await marketplace.Buy(nftRef.address, tokenId3, price, {
      from: buyer1,
    })
    const balance = await nftRef.balanceOf.call(buyer1)
    assert.equal(balance.valueOf(), 1)
  })
})


