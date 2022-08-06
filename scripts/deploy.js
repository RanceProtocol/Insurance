const { ethers, upgrades } = require("hardhat");
const treasure = require("../artifacts/contracts/RanceTreasury.sol/RanceTreasury.json");
const pro = require("../artifacts/contracts/RanceProtocol.sol/RanceProtocol.json");
const addr = "0x2c1cA1839893B21d9eAd72c0bc1d1e05841bfD82";
const addr2 = "0xaca2d837a52e141e9a6cebe33f685cc90f311356";

async function main() {
  const [admin] = await ethers.getSigners();
  const treasury = new ethers.Contract(addr, treasure.abi, admin);
  const protocol = new ethers.Contract(addr2, pro.abi, admin);

  await treasury.setInsuranceProtocolAddress(protocol.address);
  await protocol.addPaymentToken("USDT", process.env.USDT);
  await protocol.addInsureCoins(
    [
      "BTCB",
      "ETH",
      "WBNB",
      "ADA",
      "XRP",
      "DOGE",
      "LTC",
      "DOT",
      "LINK",
      "CAKE",
      "TRX",
      "UNI",
      "SUSHI",
      "AXS",
      "TWT",
      "PRED",
    ],
    [
      process.env.BTCB,
      process.env.ETH,
      process.env.WBNB,
      process.env.ADA,
      process.env.XRP,
      process.env.DOGE,
      process.env.LTC,
      process.env.DOT,
      process.env.LINK,
      process.env.CAKE,
      process.env.TRX,
      process.env.UNI,
      process.env.SUSHI,
      process.env.AXS,
      process.env.TWT,
      process.env.PRED,
    ]
  );
  await protocol.transferOwnership(process.env.ADMIN_ADDRESS);
  await treasury.addAdmin(process.env.ADMIN_ADDRESS);
}
// module.exports = [admin.getAddress()];
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
