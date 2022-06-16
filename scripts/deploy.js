const { ethers, upgrades } = require("hardhat");

async function main() {
  const admin = process.env.ADMIN_ADDRESS;
  const RanceTreasury = await ethers.getContractFactory("RanceTreasury");
  const RanceProtocol = await ethers.getContractFactory("RanceProtocol");
  const treasury = await RanceTreasury.deploy(admin);
  const protocol = await upgrades.deployProxy(
    RanceProtocol,
    [treasury.address, process.env.UNISWAP_ROUTER, process.env.RANCE_TOKEN],
    { kind: "uups" }
  );

  console.log(`
    RanceProtocol deployed to: ${protocol.address},
    RanceTreasury: ${treasury.address}`);
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
