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
    periodInSeconds,
    insuranceFees,
    uninsureFees,
    amount,
    paymentToken2,
    insureCoin2;

  beforeEach(async () => {
    [admin, user] = await ethers.getSigners();
    provider = waffle.provider;
    const adminAddress = admin.getAddress();
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
    paymentToken2 = await MockERC20.deploy("BUSD Token", "BUSD");
    insureCoin = await MockERC20.deploy("Bitcoin Token", "WBTC");
    insureCoin2 = await MockERC20.deploy("Ether Token", "WETH");
    treasury = await RanceTreasury.deploy(adminAddress);
    factory = await Factory.deploy(adminAddress);
    const weth = await Weth9.deploy();
    router = await Router.deploy(factory.address, weth.address);
    protocol = await upgrades.deployProxy(
      RanceProtocol,
      [treasury.address, router.address, rance.address, paymentToken.address],
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

    periodInSeconds = [15780000, 31560000, 63120000];
    insuranceFees = [100, 50, 25];
    uninsureFees = [
      ethers.utils.parseUnits("10"),
      ethers.utils.parseUnits("100"),
      ethers.utils.parseUnits("1000"),
    ];

    planId1 = ethers.utils.solidityKeccak256(
      ["uint32", "uint8", "uint72"],
      [periodInSeconds[0], insuranceFees[0], uninsureFees[0]]
    );

    planId2 = ethers.utils.solidityKeccak256(
      ["uint32", "uint8", "uint72"],
      [periodInSeconds[1], insuranceFees[1], uninsureFees[1]]
    );

    planId3 = ethers.utils.solidityKeccak256(
      ["uint32", "uint8", "uint72"],
      [periodInSeconds[2], insuranceFees[2], uninsureFees[2]]
    );

    amount = ethers.utils.parseUnits("200");

    await protocol.addInsureCoins(["WBTC"], [insureCoin.address]);
    await protocol.insure(
      planId1,
      amount,
      [paymentToken.address, insureCoin.address],
      "WBTC",
      "MUSD"
    );

    elapsedTime = 360 * 24 * 60 * 60;
  });

  it("Should initialize contract variable", async () => {
    expect(await protocol.uniswapRouter()).to.equal(router.address);
    expect(await protocol.treasury()).to.equal(treasury.address);
    expect(await protocol.RANCE()).to.equal(rance.address);
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

  it("Should check the total insurance locked for a token", async () => {
    expect(
      await protocol.getTotalInsuranceLocked(paymentToken.address)
    ).to.be.equal(await protocol.getInsureAmount(planId1, amount));
  });

  it("Should add a payment Token", async () => {
    const tx = await protocol.addPaymentToken("BUSD", paymentToken2.address);
    const receipt = await tx.wait();
    const actualAddress = receipt.events[1].args[1];
    expect(actualAddress).to.equal(paymentToken2.address);
  });

  it("Should only add a payment Token that is not added", async () => {
    expect(protocol.addPaymentToken("BUSD", paymentToken.address)).to.be
      .reverted;
  });

  it("Should remove a payment Token", async () => {
    const tx = await protocol.removePaymentToken("MUSD");
    const receipt = await tx.wait();
    const removedAddress = receipt.events[1].args[0];
    expect(removedAddress).to.equal(paymentToken.address);
  });

  it("Should only remove a payment Token that is added", async () => {
    expect(protocol.removePaymentToken("BUSD")).to.be.reverted;
  });

  it("Should only allow admin add payment token", async () => {
    expect(
      protocol.connect(user).addPaymentToken("BUSD", paymentToken2.address)
    ).to.be.reverted;
  });

  it("Should only allow admin remove payment token", async () => {
    expect(protocol.connect(user).removePaymentToken("MUSD")).to.be.reverted;
  });

  it("Should add an InsureCoin", async () => {
    const tx = await protocol.addInsureCoins(["WETH"], [insureCoin2.address]);
    const receipt = await tx.wait();
    const actualAddress = receipt.events[0].args[1];
    expect(actualAddress).to.equal(insureCoin2.address);
  });

  it("Should only add an InsureCoin that is not added", async () => {
    expect(protocol.addInsureCoins("WBTC", insureCoin.address)).to.be.reverted;
  });

  it("Should remove an InsureCoin", async () => {
    const tx = await protocol.removeInsureCoins(["WBTC"]);
    const receipt = await tx.wait();
    const removedAddress = receipt.events[0].args[0];
    expect(removedAddress).to.equal(insureCoin.address);
  });

  it("Should only remove an InsureCoin that is added", async () => {
    expect(protocol.removeInsureCoins("WETH")).to.be.reverted;
  });

  it("Should only allow admin add an InsureCoin", async () => {
    expect(protocol.connect(user).addInsureCoins("WETH", insureCoin2.address))
      .to.be.reverted;
  });

  it("Should only allow admin remove InsureCoin", async () => {
    expect(protocol.connect(user).removeInsureCoins("WBTC")).to.be.reverted;
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
    for (let i = 0; i < tx.length; i++) {
      const planId = ethers.utils.solidityKeccak256(
        ["uint32", "uint8", "uint72"],
        [periodInSeconds[i], insuranceFees[i], uninsureFees[i]]
      );
      expect(tx[i].planId).to.equal(planId);
      expect(tx[i].periodInSeconds).to.equal(periodInSeconds[i]);
      expect(tx[i].insuranceFee).to.equal(insuranceFees[i]);
      expect(tx[i].uninsureFee).to.equal(uninsureFees[i]);
      expect(tx[i].isActivated).to.be.true;
    }
  });

  it("Should deactivate package plan", async () => {
    await protocol.deactivatePackagePlan(planId1);
    const tx = await protocol.getAllPackagePlans();
    expect(tx[0].isActivated).to.be.false;
  });

  it("Should only deactivate package plan with valid plan id", async () => {
    const nonExistentPlanId = ethers.utils.solidityKeccak256(
      ["uint32", "uint8", "uint72"],
      [1656049378, 20, ethers.utils.parseUnits("1000")]
    );
    expect(protocol.deactivatePackagePlan(nonExistentPlanId)).to.be.reverted;
  });

  it("Should only allow admin deactivate package plan", async () => {
    expect(protocol.connect(user).deactivatePackagePlan(planId1)).to.be
      .reverted;
  });

  it("Should add a new package plan", async () => {
    const periodInSeconds = 126240000;
    const insuranceFee = 5;
    const uninsureFee = ethers.utils.parseUnits("1000");

    const tx = await protocol.addPackagePlan(
      periodInSeconds,
      insuranceFee,
      uninsureFee
    );

    const receipt = await tx.wait();

    const expectedPlanId = ethers.utils.solidityKeccak256(
      ["uint32", "uint8", "uint"],
      [periodInSeconds, insuranceFee, uninsureFee]
    );
    expect(receipt.events[0].args[0]).to.be.equal(expectedPlanId);
  });

  it("Should only allow admin add a new package plan", async () => {
    const periodInSeconds = 126240000;
    const insuranceFee = 5;
    const uninsureFee = ethers.utils.parseUnits("1000");

    expect(protocol.addPackagePlan(periodInSeconds, insuranceFee, uninsureFee))
      .to.be.reverted;
  });

  it("Should only add a new package plan thats does not exist", async () => {
    expect(
      protocol.addPackagePlan(
        periodInSeconds[0],
        insuranceFees[0],
        uninsureFees[0]
      )
    ).to.be.reverted;
  });

  it("Should purchase a package plan", async () => {
    const amount = ethers.utils.parseUnits("200");
    const tx = await protocol.insure(
      planId2,
      amount,
      [paymentToken.address, insureCoin.address],
      "WBTC",
      "MUSD"
    );

    const receipt = await tx.wait();
    expect(receipt.events[8].args[1]).to.equal(await admin.getAddress());
  });

  it("Should only purchase valid package plan", async () => {
    const amount = ethers.utils.parseUnits("200");
    const nonExistentPlanId = ethers.utils.solidityKeccak256(
      ["uint32", "uint8", "uint"],
      [126240000, 20, ethers.utils.parseUnits("1000")]
    );
    expect(
      protocol.insure(
        nonExistentPlanId,
        amount,
        [paymentToken.address, insureCoin.address],
        "WBTC",
        "MUSD"
      )
    ).to.be.reverted;
  });

  it("Should only purchase package plan with supported token", async () => {
    const amount = ethers.utils.parseUnits("200");
    expect(
      protocol.insure(
        planId2,
        amount,
        [paymentToken.address, insureCoin2.address],
        "WETH",
        "MUSD"
      )
    ).to.be.reverted;
  });

  it("Should only purchase active package plan", async () => {
    const amount = ethers.utils.parseUnits("200");
    await protocol.deactivatePackagePlan(planId1);
    expect(
      protocol.insure(
        planId1,
        amount,
        [paymentToken.address, insureCoin.address],
        "WBTC",
        "MUSD"
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
    expect(tx[0].planId).to.equal(planId1);
  });

  it("Should cancel package plan", async () => {
    let tx = await protocol.getAllUserPackages(admin.getAddress());
    await rance.approve(protocol.address, ethers.utils.parseUnits("900000"));

    await protocol.cancel(tx[0].packageId);

    tx = await protocol.getAllUserPackages(admin.getAddress());
    const ranceBalance = await rance.balanceOf(treasury.address);
    expect(tx[0].isCancelled).to.be.true;
    expect(ranceBalance).to.be.equal(ethers.utils.parseUnits("10"));
  });

  it("Should only cancel active package plan", async () => {
    await ethers.provider.send("evm_increaseTime", [elapsedTime]);
    await ethers.provider.send("evm_mine", []);

    const tx = await protocol.getAllUserPackages(admin.getAddress());
    await rance.approve(protocol.address, ethers.utils.parseUnits("900000"));

    expect(protocol.cancel(tx[0].packageId)).to.be.reverted;
  });

  it("Should only withdraw package plan when expired", async () => {
    const tx = await protocol.getAllUserPackages(admin.getAddress());
    expect(protocol.withdraw(tx[0].packageId)).to.be.reverted;
  });

  it("Should withdraw package plan when expired", async () => {
    elapsedTime = 190 * 24 * 60 * 60;
    await ethers.provider.send("evm_increaseTime", [elapsedTime]);
    await ethers.provider.send("evm_mine", []);

    let tx = await protocol.getAllUserPackages(admin.getAddress());
    await protocol.withdraw(tx[0].packageId);
    tx = await protocol.getAllUserPackages(admin.getAddress());
    expect(tx[0].isWithdrawn).to.be.true;
  });

  it("Should only withdraw package plan that does not elapsed 30days after expiration", async () => {
    await ethers.provider.send("evm_increaseTime", [elapsedTime]);
    await ethers.provider.send("evm_mine", []);

    const tx = await protocol.getAllUserPackages(admin.getAddress());
    expect(protocol.withdraw(tx[0].packageId)).to.be.reverted;
  });
});
