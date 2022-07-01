const { ethers, waffle, upgrades } = require("hardhat");
const { expect } = require("chai");

describe("Rance Treasury Contract Test", () => {
  let paymentToken, treasury, deployer, user, provider, protocol;

  beforeEach(async () => {
    [deployer, user] = await ethers.getSigners();
    provider = waffle.provider;
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    paymentToken = await MockERC20.deploy("MUSD Token", "MUSD");
    const RanceTreasury = await ethers.getContractFactory("RanceTreasury");
    const RanceProtocol = await ethers.getContractFactory("RanceProtocol");
    treasury = await RanceTreasury.deploy(deployer.getAddress());
    protocol = await upgrades.deployProxy(
      RanceProtocol,
      [
        treasury.address,
        process.env.UNISWAP_ROUTER,
        process.env.RANCE_TOKEN,
        paymentToken.address,
      ],
      { kind: "uups" }
    );
  });

  it("Should returns true if account is authorised", async () => {
    expect(await treasury.isAuthorized(deployer.getAddress())).to.be.true;
  });

  it("Should returns false if account is not authorised", async () => {
    expect(await treasury.isAuthorized(user.getAddress())).to.be.false;
  });

  it("Should set protocol address", async () => {
    const tx = await treasury.setInsuranceProtocolAddress(protocol.address);
    const receipt = await tx.wait();
    const actualAddress = receipt.events[0].args[1];
    expect(actualAddress).to.equal(protocol.address);
  });

  it("Should only allow admin set protocol address", async () => {
    expect(treasury.connect(user).setInsuranceProtocolAddress(treasury.address))
      .to.be.reverted;
  });

  it("Should withdraw BNB/CRO from treasury contract", async () => {
    const amount = ethers.utils.parseUnits("50");
    await deployer.sendTransaction({ to: treasury.address, value: amount });

    const tx = await treasury.withdraw(amount);
    const contractBalance = await provider.getBalance(treasury.address);
    const receipt = await tx.wait();
    expect(contractBalance).to.equal(ethers.BigNumber.from(0));
    expect(receipt.events[0].args[0]).to.equal(await deployer.getAddress());
    expect(receipt.events[0].args[1]).to.equal(amount);
  });

  it("Should only allow admin withdraw BNB/CRO from treasury contract", async () => {
    const amount = ethers.utils.parseUnits("50");
    await deployer.sendTransaction({ to: treasury.address, value: amount });

    expect(treasury.connect(user).withdraw(amount)).to.be.reverted;
  });

  it("Should withdraw token from treasury contract", async () => {
    const amount = ethers.utils.parseUnits("50");
    await paymentToken.transfer(treasury.address, amount);

    await paymentToken.approve(user.getAddress(), amount);
    const tx = await treasury.withdrawToken(
      paymentToken.address,
      user.getAddress(),
      amount
    );
    const userBalance = await paymentToken.balanceOf(user.getAddress());
    const receipt = await tx.wait();
    expect(userBalance).to.equal(amount);
    expect(receipt.events[1].args[0]).to.equal(await user.getAddress());
    expect(receipt.events[1].args[1]).to.equal(amount);
  });

  it("Should allow only authorised account withdraw token from treasury contract", async () => {
    const amount = ethers.utils.parseUnits("50");
    await paymentToken.transfer(treasury.address, amount);

    await paymentToken.approve(user.getAddress(), amount);
    expect(
      treasury
        .connect(user)
        .withdrawToken(paymentToken.address, user.getAddress(), amount)
    ).to.be.reverted;
  });
});
