/* eslint-disable node/no-extraneous-require */
/* eslint-disable no-unused-expressions */
const { ethers, waffle, upgrades } = require("hardhat");
const { expect } = require("chai");
const { time } = require("@openzeppelin/test-helpers");
const uniswapFactory = require("@uniswap/v2-core/build/UniswapV2Factory.json");
const uniswapRouter = require("@uniswap/v2-periphery/build/UniswapV2Router02.json");
const WETH9 = require("@uniswap/v2-periphery/build/WETH9.json");

describe("Rance Protocol Test", () => {
  let provider,
    treasury,
    protocol,
    admin,
    user,
    timestamp,
    elapsedTime,
    insureCoin,
    paymentToken,
    rance,
    factory,
    router,
    planId1,
    planId2,
    planId3,
    periodInMonths,
    insuranceFees,
    uninsureFees,
    amount;

  beforeEach(async () => {
    [admin, user] = await ethers.getSigners();
    provider = waffle.provider;
    const adminAddress = process.env.ADMIN_ADDRESS;
    const RanceTreasury = await ethers.getContractFactory("RanceTreasury");
    const RanceProtocol = await ethers.getContractFactory("RanceProtocol");
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const Factory = new ethers.ContractFactory(
      uniswapFactory.abi,
      uniswapFactory.bytecode,
      admin
    );
    const Weth9 = new ethers.ContractFactory(WETH9.abi, WETH9.bytecode, admin);
    const Router = new ethers.ContractFactory(
      uniswapRouter.abi,
      uniswapRouter.bytecode,
      admin
    );
    rance = await MockERC20.deploy("Rance Token", "RANCE");
    paymentToken = await MockERC20.deploy("MUSD Token", "MUSD");
    insureCoin = await MockERC20.deploy("Bitcoin Token", "WBTC");
    treasury = await RanceTreasury.deploy(adminAddress);
    factory = await Factory.deploy(adminAddress);
    const weth = await Weth9.deploy();
    router = await Router.deploy(factory.address, weth.address);
    protocol = await upgrades.deployProxy(
      RanceProtocol,
      [treasury.address, router.address, rance.address],
      { kind: "uups" }
    );

    timestamp = ethers.BigNumber.from((await provider.getBlock()).timestamp);

    await factory.createPair(paymentToken.address, insureCoin.address);

    await paymentToken.approve(
      protocol.address,
      ethers.utils.parseUnits("900000")
    );
    await paymentToken.approve(
      router.address,
      ethers.utils.parseUnits("900000")
    );
    await paymentToken.approve(
      treasury.address,
      ethers.utils.parseUnits("900000")
    );
    await paymentToken.transfer(
      treasury.address,
      ethers.utils.parseUnits("40000")
    );

    await insureCoin.approve(
      protocol.address,
      ethers.utils.parseUnits("900000")
    );
    await insureCoin.approve(router.address, ethers.utils.parseUnits("900000"));

    await router.addLiquidity(
      paymentToken.address,
      insureCoin.address,
      ethers.utils.parseUnits("500000"),
      ethers.utils.parseUnits("500"),
      ethers.utils.parseUnits("500000"),
      ethers.utils.parseUnits("500"),
      protocol.address,
      timestamp.add(parseInt(time.duration.minutes(5)))
    );

    await treasury.setInsuranceProtocolAddress(protocol.address);

    periodInMonths = [6, 12, 24];
    insuranceFees = [100, 50, 25];
    uninsureFees = [
      ethers.utils.parseUnits("1"),
      ethers.utils.parseUnits("10"),
      ethers.utils.parseUnits("100"),
    ];

    planId1 = ethers.utils.solidityKeccak256(
      ["uint8", "uint8", "uint72"],
      [periodInMonths[0], insuranceFees[0], uninsureFees[0]]
    );

    planId2 = ethers.utils.solidityKeccak256(
      ["uint8", "uint8", "uint72"],
      [periodInMonths[1], insuranceFees[1], uninsureFees[1]]
    );

    planId3 = ethers.utils.solidityKeccak256(
      ["uint8", "uint8", "uint72"],
      [periodInMonths[2], insuranceFees[2], uninsureFees[2]]
    );

    amount = ethers.utils.parseUnits("200");
    await protocol.insure(
      planId1,
      amount,
      insureCoin.address,
      paymentToken.address
    );

    elapsedTime = 360 * 24 * 60 * 60;
  });

  it("Should initialize contract variable", async () => {
    expect(await protocol.uniswapRouter()).to.equal(router.address);
    expect(await protocol.treasury()).to.equal(treasury.address);
    expect(await protocol.RANCE()).to.equal(rance.address);
    expect(await protocol.totalInsuranceLocked()).to.equal(
      ethers.utils.parseUnits("100")
    );
  });

  it("Should update treasury address", async () => {
    await protocol.setTreasuryAddress(treasury.address);
    expect(await protocol.treasury()).to.equal(treasury.address);
  });

  it("Should allow only owner to update treasury address", async () => {
    expect(protocol.connect(user).setTreasuryAddress(treasury.address)).to.be
      .reverted;
  });

  it("Should returns true if account is authorised in the treasury contract", async () => {
    expect(await treasury.isAuthorized(admin.getAddress())).to.be.true;
  });

  it("Should returns false if account is not authorised in the treasury contract", async () => {
    expect(await treasury.isAuthorized(router.address)).to.be.false;
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
    await admin.sendTransaction({ to: treasury.address, value: amount });

    const tx = await treasury.withdraw(amount);
    const contractBalance = await provider.getBalance(treasury.address);
    const receipt = await tx.wait();
    expect(contractBalance).to.equal(ethers.BigNumber.from(0));
    expect(receipt.events[0].args[0]).to.equal(await admin.getAddress());
    expect(receipt.events[0].args[1]).to.equal(amount);
  });

  it("Should only allow admin withdraw BNB/CRO from treasury contract", async () => {
    const amount = ethers.utils.parseUnits("50");
    await admin.sendTransaction({ to: treasury.address, value: amount });

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

  it("Should returns all package plans", async () => {
    const tx = await protocol.getAllPackagePlans();
    const periodInMonths = [6, 12, 24];
    const insuranceFees = [100, 50, 25];
    const uninsureFees = [
      ethers.utils.parseUnits("1"),
      ethers.utils.parseUnits("10"),
      ethers.utils.parseUnits("100"),
    ];
    for (let i = 0; i < tx.length; i++) {
      const planId = ethers.utils.solidityKeccak256(
        ["uint8", "uint8", "uint72"],
        [periodInMonths[i], insuranceFees[i], uninsureFees[i]]
      );
      expect(tx[i].planId).to.equal(planId);
      expect(tx[i].periodInMonths).to.equal(periodInMonths[i]);
      expect(tx[i].insuranceFee).to.equal(insuranceFees[i]);
      expect(tx[i].uninsureFee).to.equal(uninsureFees[i]);
    }
  });

  it("Should update package plan", async () => {
    const uninsureFee = ethers.utils.parseUnits("20");
    await protocol.updatePackagePlans(
      [planId2],
      [periodInMonths[1]],
      [insuranceFees[1]],
      [uninsureFee]
    );
    const tx = await protocol.getAllPackagePlans();
    expect(tx[1].planId).to.equal(planId2);
    expect(tx[1].periodInMonths).to.equal(periodInMonths[1]);
    expect(tx[1].insuranceFee).to.equal(insuranceFees[1]);
    expect(tx[1].uninsureFee).to.equal(uninsureFee);
  });

  it("Should update package plans", async () => {
    const uninsureFee1 = ethers.utils.parseUnits("2");
    const uninsureFee2 = ethers.utils.parseUnits("20");
    const uninsureFee3 = ethers.utils.parseUnits("200");
    await protocol.updatePackagePlans(
      [planId1, planId2, planId3],
      [periodInMonths[0], periodInMonths[1], periodInMonths[2]],
      [insuranceFees[0], insuranceFees[1], insuranceFees[2]],
      [uninsureFee1, uninsureFee2, uninsureFee3]
    );
    const tx = await protocol.getAllPackagePlans();
    expect(tx[0].planId).to.equal(planId1);
    expect(tx[0].periodInMonths).to.equal(periodInMonths[0]);
    expect(tx[0].insuranceFee).to.equal(insuranceFees[0]);
    expect(tx[0].uninsureFee).to.equal(uninsureFee1);
    expect(tx[1].planId).to.equal(planId2);
    expect(tx[1].periodInMonths).to.equal(periodInMonths[1]);
    expect(tx[1].insuranceFee).to.equal(insuranceFees[1]);
    expect(tx[1].uninsureFee).to.equal(uninsureFee2);
    expect(tx[2].planId).to.equal(planId3);
    expect(tx[2].periodInMonths).to.equal(periodInMonths[2]);
    expect(tx[2].insuranceFee).to.equal(insuranceFees[2]);
    expect(tx[2].uninsureFee).to.equal(uninsureFee3);
  });

  it("Should allow only owner to update predict amount", async () => {
    const uninsureFee = ethers.utils.parseUnits("20");
    expect(
      protocol.updatePackagePlans(
        [planId2],
        [periodInMonths[1]],
        [insuranceFees[1]],
        [uninsureFee]
      )
    ).to.be.reverted;
  });

  it("Should add a new package plan", async () => {
    const periodInMonths = 48;
    const insuranceFee = 5;
    const uninsureFee = ethers.utils.parseUnits("1000");

    await protocol.addPackagePlan(periodInMonths, insuranceFee, uninsureFee);

    const expectedPlanId = ethers.utils.solidityKeccak256(
      ["uint8", "uint8", "uint"],
      [periodInMonths, insuranceFee, uninsureFee]
    );

    const actualPlanId = await protocol.getAllPackagePlans();
    expect(actualPlanId[3].planId).to.equal(expectedPlanId);
  });

  it("Should only allow admin add a new package plan", async () => {
    const periodInMonths = 48;
    const insuranceFee = 5;
    const uninsureFee = ethers.utils.parseUnits("1000");

    expect(protocol.addPackagePlan(periodInMonths, insuranceFee, uninsureFee))
      .to.be.reverted;
  });

  it("Should purchase a package plan", async () => {
    const amount = ethers.utils.parseUnits("200");
    const insureAmount = await protocol.getInsureAmount(planId2, amount);
    const tx = await protocol.insure(
      planId2,
      amount,
      insureCoin.address,
      paymentToken.address
    );

    const receipt = await tx.wait();
    expect(receipt.events[10].args[0]).to.equal(await admin.getAddress());
    expect(receipt.events[10].args[1]).to.equal(insureCoin.address);
    expect(receipt.events[10].args[2]).to.equal(insureAmount);
    expect(receipt.events[10].args[4].planId).to.equal(planId2);
    expect(receipt.events[10].args[4].periodInMonths).to.equal(
      periodInMonths[1]
    );
    expect(receipt.events[10].args[4].insuranceFee).to.equal(insuranceFees[1]);
    expect(receipt.events[10].args[4].uninsureFee).to.equal(uninsureFees[1]);
  });

  it("Should only purchase valid package plan", async () => {
    const amount = ethers.utils.parseUnits("200");
    const nonExistentPlanId = ethers.utils.solidityKeccak256(
      ["uint8", "uint8", "uint"],
      [4, 20, ethers.utils.parseUnits("1000")]
    );
    expect(
      protocol.insure(
        nonExistentPlanId,
        amount,
        insureCoin.address,
        paymentToken.address
      )
    ).to.be.reverted;
  });

  it("Should return user packages", async () => {
    const insureAmount = await protocol.getInsureAmount(planId1, amount);
    const tx = await protocol.getAllUserPackages(admin.getAddress());
    expect(tx[0].user).to.equal(await admin.getAddress());
    expect(tx[0].initialDeposit).to.equal(insureAmount);
    expect(tx[0].isCancelled).to.be.false;
    expect(tx[0].isWithdrawn).to.be.false;
    expect(tx[0].insureCoin).to.equal(insureCoin.address);
    expect(tx[0].paymentToken).to.equal(paymentToken.address);
    expect(tx[0].packagePlan.planId).to.equal(planId1);
    expect(tx[0].packagePlan.periodInMonths).to.equal(periodInMonths[0]);
    expect(tx[0].packagePlan.insuranceFee).to.equal(insuranceFees[0]);
    expect(tx[0].packagePlan.uninsureFee).to.equal(uninsureFees[0]);
  });

  it("Should cancel package plan", async () => {
    await rance.approve(protocol.address, ethers.utils.parseUnits("900000"));

    await protocol.cancel(planId1);

    const tx = await protocol.getAllUserPackages(admin.getAddress());
    expect(tx[0].isCancelled).to.be.true;
  });

  it("Should only cancel active package plan", async () => {
    await ethers.provider.send("evm_increaseTime", [elapsedTime]);
    await ethers.provider.send("evm_mine", []);

    await rance.approve(protocol.address, ethers.utils.parseUnits("900000"));

    expect(protocol.cancel(planId1)).to.be.reverted;
  });

  it("Should only withdraw package plan when expired", async () => {
    expect(protocol.withdraw(planId1)).to.be.reverted;
  });

  it("Should withdraw package plan when expired", async () => {
    await ethers.provider.send("evm_increaseTime", [elapsedTime]);
    await ethers.provider.send("evm_mine", []);

    await protocol.withdraw(planId1);
    const tx = await protocol.getAllUserPackages(admin.getAddress());
    expect(tx[0].isWithdrawn).to.be.true;
  });
});
