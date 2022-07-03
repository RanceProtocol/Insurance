const { ethers, upgrades } = require("hardhat");
const factory = require("../artifacts/contracts/MockERC20.sol/MockERC20.json");

async function main() {
  const [admin, user] = await ethers.getSigners();
  // const RanceTreasury = await ethers.getContractFactory("RanceTreasury");
  const RanceProtocol = await ethers.getContractFactory("RanceProtocol");
  // const MockERC20 = await ethers.getContractFactory("MockERC20");
  const rance = new ethers.Contract(
    process.env.RANCE_TOKEN,
    factory.abi,
    admin
  );
  const addr = "0x39A12f5704E52277c9c9949bD4663e3ACaC4807c";
  const musd = new ethers.Contract(process.env.MUSD, factory.abi, admin);

  await rance.approve(addr, ethers.utils.parseUnits("10000"));
  await musd.approve(addr, ethers.utils.parseUnits("10000"));
  await rance.transfer(addr, ethers.utils.parseUnits("10000"));
  await musd.transfer(addr, ethers.utils.parseUnits("10000"));
  // const rance = await MockERC20.deploy("Rance Token", "RANCE");
  /* const protocol = await upgrades.deployProxy(
    RanceProtocol,
    [
      process.env.TREASURY,
      process.env.UNISWAP_ROUTER,
      process.env.RANCE_TOKEN,
      process.env.MUSD,
    ],
    { kind: "uups" }
  );

  await treasury.setInsuranceProtocolAddress(protocol.address);
  await protocol.setTreasuryAddress(treasury.address);
  await protocol.addInsureCoins(
    ["BTC", "ETH", "CRO"],
    [process.env.BTC, process.env.ETH, process.env.CRO]
  );
  await protocol.transferOwnership(process.env.ADMIN_ADDRESS);

  console.log(`
    RanceProtocol deployed to: ${protocol.address}`); */
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
