const { ethers, upgrades } = require("hardhat");
const treasure = require("../artifacts/contracts/RanceTreasury.sol/RanceTreasury.json");
const pro = require("../artifacts/contracts/RanceProtocol.sol/RanceProtocol.json");
const addr = "0xD032336EB682E702A4AAEDd15140733421a66150";
const addr2 = "0xDFe999B28A48BFb5DD674D3899B77fd4fF5CF46c";

async function main() {
  const [admin] = await ethers.getSigners();
  const Treasury = await ethers.getContractFactory("RanceTreasury");
  const Protocol = await ethers.getContractFactory("RanceProtocol");
  const treasury = await Treasury.deploy(admin.getAddress());
  const protocol = await upgrades.deployProxy(
    Protocol,
    [treasury.address, process.env.UNISWAP_ROUTER, process.env.USDT],
    { kind: "uups" }
  );
  /* const MockERC20 = await ethers.getContractFactory("MockERC20");
  const rance = await MockERC20.deploy("Rance Token", "RANCE"); */

  await treasury.setInsuranceProtocolAddress(protocol.address);
  await protocol.addPaymentToken("USDC", process.env.USDC);
  await protocol.updateReferralReward(ethers.BigNumber.from("5"));
  await protocol.addInsureCoins(
    ["SPHYNX", "WBRISE", "BNB"],
    [process.env.SPHYNX, process.env.WBRISE, process.env.BNB]
  );

  // await protocol.transferOwnership(process.env.ADMIN_ADDRESS);
  // await treasury.addAdmin(process.env.ADMIN_ADDRESS);
  console.log(`Protocol: ${protocol.address},
  Treasury: ${treasury.address}`);
}
// module.exports = [admin.getAddress()];
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
