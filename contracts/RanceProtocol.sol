//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./interfaces/IRanceTreasury.sol";
import "hardhat/console.sol";

contract RanceProtocol is 
    Initializable, 
    UUPSUpgradeable, 
    OwnableUpgradeable, 
    ReentrancyGuardUpgradeable{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint;

    IUniswapV2Router02 public uniswapRouter;

    /**
    *  @dev Instance of the insurance treasury (used to handle insurance funds).
    */
    IRanceTreasury public treasury;

    /**
    *  @dev Instance of RANCE token
    */
    IERC20Upgradeable public RANCE;


    /** 
    * @dev list of package plan ids
    */
    bytes32[] public packagePlanIds;

    /** 
    * @dev Total number of payment token
    */

    uint public noPaymentTokens;


    /** 
    * @dev Total number of insure coins
    */

    uint public noInsureCoins;


    /**
     * @dev data of Package Plan on the Insurance Protocol
     */
    struct PackagePlan {
        bytes32 planId;
        uint32 periodInSeconds;
        uint8 insuranceFee;
        uint uninsureFee;
        bool isActivated; 
    }


    /**
     * @dev data of Package on the Insurance Protocol
     */
    struct Package { 
        address user;
        bytes32 planId;
        bytes32 packageId;
        uint initialDeposit; 
        uint insureOutput;
        uint startTimestamp;
        uint endTimestamp;
        bool isCancelled;
        bool isWithdrawn;
        address insureCoin;
        address paymentToken;
    }

    /**
     * @dev list of all package ids purchased per user
     */
    mapping(address => bytes32[]) public userToPackageIds; 

    /**
     *  @dev retrieve packagePlan with packagePlan id
     */
    mapping (bytes32 => PackagePlan) public planIdToPackagePlan;


    /**
     *  @dev retrieve package with package id
     */
    mapping (bytes32 => Package) public packageIdToPackage;


    /**
     * @dev retrieve payment token  with name
     */
    mapping(string => address) public paymentTokenNameToAddress;


    /**
     * @dev retrieve insure coin with name
     */
    mapping(string => address) public insureCoinNameToAddress;


    /**
     * @dev retrieve payment token total insurance locked  with address
     */
    mapping(address => uint) public totalInsuranceLocked;


    /**
     * @dev check if payment token is added
     */
    mapping(address => bool) public paymentTokenAdded;

    /**
     * @dev check if insure Coin is added
     */
    mapping(address => bool) public insureCoinAdded;


    /**
     * @dev Emitted when an insurance package is activated
     */
    event InsuranceActivated(
        bytes32 indexed _packageId,
        address indexed _user
    );


    /**
     * @dev Emitted when an insurance package is cancelled
     */
    event InsuranceCancelled(
        bytes32 indexed _packageId,
        address indexed _user
    );

    /**
     * @dev Emitted when a payment token is added
     */
    event PaymentTokenAdded(string paymentTokenName, address indexed paymentToken);


    /**
     * @dev Emitted when a payment token is removed
     */
    event PaymentTokenRemoved(address indexed paymentToken);


     /**
     * @dev Emitted when a insure coin is added
     */
    event InsureCoinAdded(string insureCoinName, address indexed insureCoin);


    /**
     * @dev Emitted when a insure coin is removed
     */
    event InsureCoinRemoved(address indexed insureCoin);


    /**
     * @dev Emitted when an insurance package is withdrawn
     */
    event InsuranceWithdrawn(
        bytes32 indexed _packageId, 
        address indexed _user
    );

    /**
     * @dev Emitted when a package plan is deactivated
     */
    event PackagePlanDeactivated(bytes32 indexed _id);

    /**
     * @dev Emitted when a package plan is added
     */
    event PackagePlanAdded(
        bytes32 indexed _id,
        uint indexed _uninsureFee,
        uint8 indexed _insuranceFee,
        uint32 indexed _periodInSeconds
    );


    /**
     * @dev Emitted when the treasury address is set
     */
    event TreasuryAddressSet(address indexed _address);

    /**
     * @dev check that the address passed is not 0. 
     */
    modifier notAddress0(address _address) {
        require(_address != address(0), "Rance Protocol: Address 0 is not allowed");
        _;
    }


    /**
     * @notice Contract constructor
     * @param _treasuryAddress treasury contract address
     * @param _uniswapRouter mmfinance router address
     * @param _rance RANCE token address
     */
    function initialize(
        address _treasuryAddress,
         address _uniswapRouter,
         address _rance,
         address _paymentToken)
        public initializer { 
        __Ownable_init();
        treasury = IRanceTreasury(_treasuryAddress);
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        RANCE = IERC20Upgradeable(_rance);
        paymentTokenNameToAddress["MUSD"] = _paymentToken;
        paymentTokenAdded[_paymentToken] = true;
        totalInsuranceLocked[_paymentToken] = 0;
        noPaymentTokens = 1;
        uint32[3] memory periodInSeconds = [15780000, 31560000, 63120000];
        uint8[3] memory insuranceFees = [100, 50, 25];
        uint72[3] memory uninsureFees = [10 ether, 100 ether, 1000 ether];
        bytes32[3] memory ids = [
            keccak256(abi.encodePacked(periodInSeconds[0],insuranceFees[0],uninsureFees[0])),
            keccak256(abi.encodePacked(periodInSeconds[1],insuranceFees[1],uninsureFees[1])),
            keccak256(abi.encodePacked(periodInSeconds[2],insuranceFees[2],uninsureFees[2]))
        ];
        for (uint i = 0; i < 3; i = i + 1 ) {
            planIdToPackagePlan[ids[i]] = PackagePlan(
                ids[i],
                periodInSeconds[i],
                insuranceFees[i],
                uninsureFees[i],
                true);
            packagePlanIds.push(ids[i]);   
        }
        IERC20Upgradeable(_paymentToken).approve(address(uniswapRouter), type(uint256).max);

    }

    /**
     * @notice Authorizes upgrade allowed to only proxy 
     * @param newImplementation the address of the new implementation contract 
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner{}

    /**
     * @notice sets the address of the rance protocol treasury contract
     * @param _treasuryAddress the address of treasury
     */
    function setTreasuryAddress(address _treasuryAddress)
        external 
        onlyOwner notAddress0(_treasuryAddress)
    {
        treasury = IRanceTreasury(_treasuryAddress);
        emit TreasuryAddressSet(_treasuryAddress);
    }

    /**
     * @notice get the totalinsurancelocked of a payment token
     * @param _token the address of treasury
     * @return totalInsuranceLocked the total insurance locked of a token
     */
    function getTotalInsuranceLocked(address _token)
        external view returns(uint)
    {
        return totalInsuranceLocked[_token];
    }


    /**
     * @notice deactivate package plan
     * @param _planId the package plan id
     */
    function deactivatePackagePlan(bytes32 _planId) external onlyOwner{
        require(!planExists(_planId), "Rance Protocol: PackagePlan already exists");

        PackagePlan storage packagePlan = planIdToPackagePlan[_planId];
        packagePlan.isActivated = false;
        
        emit PackagePlanDeactivated(_planId);
    }


    /**
     * @notice adds package plan
     * @param _periodInSeconds the periods of the package in Seconds
     * @param _insuranceFee the insurance fee for the package in percentage
     * @param _uninsureFee the penalty amount for insurance cancellation
     */
    function addPackagePlan(
        uint32 _periodInSeconds,
        uint8 _insuranceFee,
        uint _uninsureFee) external onlyOwner returns(bytes32){

        bytes32 _planId = keccak256(abi.encodePacked(
            _periodInSeconds,
            _insuranceFee,
            _uninsureFee));
        
        require(!planExists(_planId), "Rance Protocol: PackagePlan already exists");

        planIdToPackagePlan[_planId] = PackagePlan(
            _planId,
            _periodInSeconds, 
            _insuranceFee, 
            _uninsureFee,
            true
        );

        packagePlanIds.push(_planId); 


        emit PackagePlanAdded(
            _planId,
            _uninsureFee, 
            _insuranceFee, 
            _periodInSeconds
        );

        return _planId;
    }


    /**
    @notice Method for adding payment token
    @dev Only admin
    @param _tokenName ERC20 token name
    @param _token ERC20 token address
    */
    function addPaymentToken(string memory _tokenName,address _token) external onlyOwner {
        require(!paymentTokenAdded[_token], "Rance Protocol:paymentToken already added");
        paymentTokenAdded[_token] = true;
        paymentTokenNameToAddress[_tokenName] = _token;
        totalInsuranceLocked[_token] = 0;
        noPaymentTokens += 1;
        IERC20Upgradeable(_token).approve(address(uniswapRouter), type(uint256).max);

        emit PaymentTokenAdded(_tokenName, _token);
    }

    /**
    @notice Method for removing payment token
    @dev Only admin
    @param _token ERC20 token address
    */
    function removePaymentToken(address _token) external onlyOwner {
        require(paymentTokenAdded[_token], "Rance Protocol:paymentToken already added");
        paymentTokenAdded[_token] = false;
        noPaymentTokens -= 1;
        IERC20Upgradeable(_token).approve(address(uniswapRouter), 0);

        emit PaymentTokenRemoved(_token);
    }


    /**
    @notice Method for adding insure coins
    @dev Only admin
    @param _tokenNames array of ERC20 token name
    @param _tokens array of  ERC20 token address
    */
    function addInsureCoins(string[] memory _tokenNames, address[] memory _tokens) external onlyOwner {
        for (uint i = 0; i < _tokenNames.length; i = i + 1) {
            require(!insureCoinAdded[_tokens[i]], "Rance Protocol:insureCoin already added");
            insureCoinAdded[_tokens[i]] = true;
            insureCoinNameToAddress[_tokenNames[i]] = _tokens[i];
            noInsureCoins += 1;

            emit InsureCoinAdded(_tokenNames[i], _tokens[i]);
        }
    }

    /**
    @notice Method for removing insure coins
    @dev Only admin
    @param _tokens array of ERC20 token address
    */
    function removeInsureCoins(address[] memory _tokens) external onlyOwner {
        for (uint i = 0; i < _tokens.length; i = i + 1) {
            require(!insureCoinAdded[_tokens[i]], "Rance Protocol:insureCoin already added");
            insureCoinAdded[_tokens[i]] = false;
            noInsureCoins -= 1;

            emit InsureCoinRemoved(_tokens[i]);
        }
    }


    /**
     * @notice get all package plans
     * @return packagePlans return array of package plans
     */
    function getAllPackagePlans() external view returns(PackagePlan[] memory){
        uint length = packagePlanIds.length;
        PackagePlan[] memory output = new PackagePlan[](length);
        uint index = 0;
        for (uint i = 0; i < length; i = i + 1) {
            output[index] = planIdToPackagePlan[packagePlanIds[i]];
            index = index + 1;
        }
        return output;
    }
    

    /**
     * @notice purchases an insurance package 
     * @param _planId      id of the package plan 
     * @param _amount the amount deposited
     * @param _insureCoin the insureCoin choosen by the user
     * @param _paymentToken the payment token deposited
     */
    function insure
    (
        address[] memory path,
        bytes32 _planId,
        uint _amount,
        string memory _insureCoin,
        string memory _paymentToken
        ) external{
        require(planIdToPackagePlan[_planId].isActivated, "Rance Protocol: PackagePlan not active");
        uint insureAmount = getInsureAmount(_planId, _amount);
        uint insuranceFee = _amount.sub(insureAmount);
        address paymentToken = paymentTokenNameToAddress[_paymentToken];
        address insureCoin = insureCoinNameToAddress[_insureCoin];

        IERC20Upgradeable(paymentToken).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20Upgradeable(paymentToken).approve(address(treasury), insuranceFee);
        IERC20Upgradeable(paymentToken).safeTransfer(address(treasury), insuranceFee);
        uint swapOutput = _swap(msg.sender, path, insureAmount);

        totalInsuranceLocked[paymentToken] += insureAmount;
        uint startTimestamp = block.timestamp;
        uint endTimestamp = (block.timestamp).add(uint(planIdToPackagePlan[_planId].periodInSeconds).mul(30 days));
        bytes32 _packageId = keccak256(abi.encodePacked(
            msg.sender,
            insureAmount,
            startTimestamp,
            endTimestamp,
            paymentToken,
            insureCoin));

        require(!packageExists(_packageId), "Rance Protocol: Package exist");

        Package memory package = Package({
            user: msg.sender,
            planId: _planId,
            packageId: _packageId,
            initialDeposit: insureAmount,
            insureOutput: swapOutput,
            startTimestamp: startTimestamp,
            endTimestamp: endTimestamp,
            isCancelled: false,
            isWithdrawn: false,
            insureCoin: insureCoin,
            paymentToken: paymentToken
        });

        packageIdToPackage[_packageId] = package;
        userToPackageIds[msg.sender].push(_packageId);
        

        emit InsuranceActivated(
            _packageId,
            msg.sender
        );
    }

    /**
     * @notice get all user packages
     * @return Package return array of user packages
     */
    function getAllUserPackages(address _user) external view returns(Package[] memory) {
        uint length = userToPackageIds[_user].length;
        Package[] memory output = new Package[](length);
        for(uint i = 0; i < length; i = i + 1){
            output[i] = packageIdToPackage[userToPackageIds[_user][i]];
        }
        
        return output;
    }

    /**
     * @notice cancel insurance package
     * @param _packageId id of package to cancel
     */
    function cancel(bytes32 _packageId) external nonReentrant{
        require(packageExists(_packageId), "Rance Protocol: Package does not exist");

        Package storage userPackage = packageIdToPackage[_packageId];
        require(isPackageActive(userPackage) && 
        !userPackage.isCancelled, "Rance Protocol: Package Not Cancellable");

        userPackage.isCancelled = true;
        userPackage.isWithdrawn = true;
        totalInsuranceLocked[userPackage.paymentToken] -= userPackage.initialDeposit;

        IERC20Upgradeable(userPackage.insureCoin).safeTransferFrom(
            msg.sender,
            address(treasury),
            userPackage.insureOutput
        );

        RANCE.safeTransferFrom(
            msg.sender,
            address(treasury), 
            planIdToPackagePlan[userPackage.planId].uninsureFee
        );

        treasury.withdrawToken(
            userPackage.paymentToken, 
            msg.sender, 
            userPackage.initialDeposit
        );     

       
        emit InsuranceCancelled(
            _packageId, 
            msg.sender
        );
    }


    /**
     * @notice withdraw insurance package
     * @param _packageId id of package to withdraw
     */
    function withdraw(bytes32 _packageId) external nonReentrant{
        require(packageExists(_packageId), "Rance Protocol: Package does not exist");

        Package storage userPackage = packageIdToPackage[_packageId];
        require(!isPackageActive(userPackage) && 
        !userPackage.isWithdrawn && !userPackage.isCancelled && 
        userPackage.endTimestamp.add(30 days) < block.timestamp,
         "Rance Protocol: Package Not Withdrawable");

        userPackage.isWithdrawn = true;
        totalInsuranceLocked[userPackage.paymentToken] -= userPackage.initialDeposit;

        IERC20Upgradeable(userPackage.insureCoin).safeTransferFrom(
            msg.sender,
            address(treasury),
            userPackage.insureOutput
        );

        treasury.withdrawToken(
            userPackage.paymentToken, 
            msg.sender, 
            userPackage.initialDeposit
        );     

        emit InsuranceWithdrawn(
            _packageId, 
           msg.sender
        );
    } 

    /**
     * @notice get the calculated insure Amount
     * @param _planId id of the package plan
     * @param _amount amount to be calculate
     * @return insureAmount return the insure Amount from amount 
     */
    function getInsureAmount(
        bytes32 _planId, 
        uint _amount) public view returns(uint){
        require(planExists(_planId), "RanceProtocol: Plan does not exist");
        PackagePlan memory packagePlan = planIdToPackagePlan[_planId];
        uint percentage = packagePlan.insuranceFee; 
        uint numerator = 10000;
        uint insureAmount = ((numerator.div(percentage.add(100))).mul(_amount)).div(100);
        return insureAmount;
    }

    /**
     * @notice Determines whether a package exists with the given id
     * @param _packageId the id of a package
     * @return true if package exists and its id is valid
     */
    function packageExists(bytes32 _packageId)private view returns (bool){
        Package memory package = packageIdToPackage[_packageId];
        if (keccak256(abi.encodePacked(package.packageId)) == "") {
            return false;
        }

        return (keccak256(abi.encodePacked(package.packageId)) == keccak256(abi.encodePacked(_packageId)));
    }

    /**
     * @notice Determines whether a package exists with the given id
     * @param _planId the id of a package plan
     * @return true if package plan exists and its id is valid
     */
    function planExists(bytes32 _planId)private view returns (bool){
        PackagePlan memory packagePlan = planIdToPackagePlan[_planId];
        if (keccak256(abi.encodePacked(packagePlan.planId)) == "") {
            return false;
        }

        return (keccak256(abi.encodePacked(packagePlan.planId)) == keccak256(abi.encodePacked(_planId)));
    }


    function _swap(
        address _to,
        address[] memory path,
        uint _amount
    ) private returns(uint){
        uint deadline = block.timestamp;
        uint amountOutMin = uniswapRouter.getAmountsOut(_amount, path)[path.length - 1];
        uint[] memory amounts = uniswapRouter.swapExactTokensForTokens(_amount, amountOutMin, path, _to, deadline);

        return amounts[1];
    }


    function isPackageActive(Package memory package) public view returns(bool){
        return block.timestamp <= package.endTimestamp;
    }

}