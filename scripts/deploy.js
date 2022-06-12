const { ethers, upgrades } = require("hardhat");

async function main() {
  const admin = process.env.ADMIN_ADDRESS;
  const [deployer] = await ethers.getSigners();
  const RanceTreasury = await ethers.getContractFactory("RanceTreasury");
  const RanceProtocol = await ethers.getContractFactory("RanceProtocol");
  const MockERC20 = await ethers.getContractFactory("MockERC20");
  const mockRance = await MockERC20.deploy("Rance Token", "RANCE");
  const treasury = await RanceTreasury.deploy(deployer.getAddress());
  const protocol = await upgrades.deployProxy(
    RanceProtocol,
    [treasury.address, process.env.UNISWAP_ROUTER, mockRance.address],
    { kind: "uups" }
  );

  console.log(`
    RanceProtocol deployed to: ${protocol.address},);
    RanceTreasury: ${treasury.address}`);
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
