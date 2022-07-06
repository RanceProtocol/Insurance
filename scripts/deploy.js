const { ethers, upgrades } = require("hardhat");
let admin;
async function main() {
  [admin] = await ethers.getSigners();
  const RanceTreasury = await ethers.getContractFactory("RanceTreasury");
  const RanceProtocol = await ethers.getContractFactory("RanceProtocol");
  const treasury = await RanceTreasury.deploy(admin.getAddress());
  const protocol = await upgrades.deployProxy(
    RanceProtocol,
    [
      treasury.address,
      process.env.UNISWAP_ROUTER,
      process.env.RANCE_TOKEN,
      process.env.MUSD,
    ],
    { kind: "uups" }
  );

  await treasury.setInsuranceProtocolAddress(protocol.address);
  await protocol.setTreasuryAddress(treasury.address);
  await protocol.addInsureCoins(
    ["BTC", "ETH", "CRO", "MMF"],
    [process.env.BTC, process.env.ETH, process.env.CRO, process.env.MMF]
  );
  await protocol.transferOwnership(process.env.ADMIN_ADDRESS);
  await treasury.addAdmin(process.env.ADMIN_ADDRESS);

  console.log(`
    RanceProtocol deployed to: ${protocol.address},
    RanceTreasurt deployed to: ${treasury.address}`);
}
module.exports = [admin.getAddress()];
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
