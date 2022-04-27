const marketplace = artifacts.require("./Marketplace.sol");

contract("Marketplace", async (accounts) => {
  it("list asks", async () => {
    

    const marketplaceRef = await marketplace.deployed();

    const  asks = await marketplaceRef.asks.call(accounts[0],[0][0])

    console.log("asks",asks)

    assert.isAbove(asks.length, 1, 'more that 0');

    
  });
});