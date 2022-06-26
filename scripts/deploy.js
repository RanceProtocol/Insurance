const { ethers, upgrades } = require("hardhat");

async function main() {
  const admin = "";
  const RanceTreasury = await ethers.getContractFactory("RanceTreasury");
  const RanceProtocol = await ethers.getContractFactory("RanceProtocol");
  const MockERC20 = await ethers.getContractFactory("MockERC20");
  const treasury = await RanceTreasury.deploy(admin);
  const rance = await MockERC20.deploy("Rance Token", "RANCE");
  const protocol = await upgrades.deployProxy(
    RanceProtocol,
    [
      treasury.address,
      process.env.UNISWAP_ROUTER,
      rance.address,
      process.env.PAYMENT_TOKEN,
    ],
    { kind: "uups" }
  );

  await treasury.setInsuranceProtocolAddress(protocol.address);
  await protocol.setTreasuryAddress(treasury.address);
  await protocol.addInsureCoins(
    ["BTC", "ETH", "CRO", "MMF"],
    [process.env.BTC, process.env.ETH, process.env.CRO, process.env.MMF]
  );
  await protocol.transferOwnership(admin);
  await treasury.addAdmin(process.env.ADMIN_ADDRESS);


  console.log(`
    RanceProtocol deployed to: ${protocol.address},
    RanceToken: ${rance.address},
    RanceTreasury: ${treasury.address}`);
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
