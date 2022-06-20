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
    * @dev Total Insurance Locked amount
    */
    uint public totalInsuranceLocked;

    /** 
    * @dev list of package plan
    */

    PackagePlan[] public packagePlans;

    /** 
    * @dev Total number of payment token
    */

    uint public noPaymentTokens;

    /**
     * @dev data of Package Plan on the Insurance Protocol
     */
    struct PackagePlan {
        bytes32 planId;
        uint8 periodInMonths;
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
     * @dev list of all packagePlan ids purchased per user
     */
    mapping(address => bytes32[]) public userToPlans; 

    /**
     *  @dev retrieve packagePlan with packagePlan id
     */
    mapping (bytes32 => PackagePlan) public planIdToPackagePlan;

     /**
     *  @dev retrieve user package with packagePlan id
     */
    mapping(bytes32 => mapping(address => Package)) public planToUserPackage;

    /**
     * @dev retrieve payment token index  with name
     */
    mapping(string => address) public paymentTokenNameToAddress;


    /**
     * @dev check if payment token is added
     */
    mapping(address => bool) public added;


    /**
     * @dev Emitted when an insurance package is activated
     */
    event InsuranceActivated(
        bytes32 indexed _planId,
        address indexed _user
    );


    /**
     * @dev Emitted when an insurance package is cancelled
     */
    event InsuranceCancelled(
        bytes32 indexed _planId,
        address indexed _user
    );

    /**
     * @dev Emitted when a payment token is added
     */
    event PaymentTokenAdded(string paymentTokenName, address indexed paymentToken);


    /**
     * @dev Emitted when a payment token is removed
     */
    event PaymentTokenRemoved(string paymentTokenName, address indexed paymentToken);


    /**
     * @dev Emitted when an insurance package is withdrawn
     */
    event InsuranceWithdrawn(
        bytes32 indexed planId, 
        address indexed _user
    );

    /**
     * @dev Emitted when a package plan is deactivated
     */
    event PackagePlanDeactivated(bytes32 _id);

    /**
     * @dev Emitted when a package plan is added
     */
    event PackagePlanAdded(
        bytes32 _id,
        uint _uninsureFee,
        uint8 _insuranceFee,
        uint8 _periodInMonths
    );


    /**
     * @dev Emitted when the treasury address is set
     */
    event TreasuryAddressSet(address _address);

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
        totalInsuranceLocked = 0;
        paymentTokenNameToAddress["MUSD"] = _paymentToken;
        noPaymentTokens = 1;
        uint8[3] memory periodInMonths = [6,12,24];
        uint8[3] memory insuranceFees = [100, 50, 25];
        uint72[3] memory uninsureFees = [1 ether, 10 ether, 100 ether];
        bytes32[3] memory ids = [
            keccak256(abi.encodePacked(periodInMonths[0],insuranceFees[0],uninsureFees[0])),
            keccak256(abi.encodePacked(periodInMonths[1],insuranceFees[1],uninsureFees[1])),
            keccak256(abi.encodePacked(periodInMonths[2],insuranceFees[2],uninsureFees[2]))
        ];
        for (uint i = 0; i < 3; i = i + 1 ) {
            planIdToPackagePlan[ids[i]] = PackagePlan(
                ids[i],
                periodInMonths[i],
                insuranceFees[i],
                uninsureFees[i],
                true);
            packagePlans.push(planIdToPackagePlan[ids[i]]);   
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
     * @notice updates package plan
     * @param _planIds the array of package plan id
     * @param _periodInMonths the array of periods of the package in Months
     * @param _insuranceFees the array of insurance fee for the package in percentage
     * @param _uninsureFees the array of penalty amount for insurance cancellation
     */
    function updatePackagePlans(
        bytes32[] memory _planIds,
        uint8[] memory  _periodInMonths,
        uint8[] memory _insuranceFees,
        uint[] memory _uninsureFees) external onlyOwner{

        for (uint i = 0; i < _planIds.length; i = i + 1 ) {
            PackagePlan storage packagePlan = planIdToPackagePlan[_planIds[i]];
            packagePlan.isActivated = false;

            bytes32 _planId = keccak256(abi.encodePacked(
            _periodInMonths[i],
            _insuranceFees[i],
            _uninsureFees[i]));
        
            require(!planExists(_planId), "Rance Protocol: PackagePlan already exists");

            planIdToPackagePlan[_planId] = PackagePlan(
                _planId,
                _periodInMonths[i], 
                _insuranceFees[i], 
                _uninsureFees[i],
                true
            );

            packagePlans.push(planIdToPackagePlan[_planId]); 
            
            emit PackagePlanDeactivated(_planIds[i]);

            emit PackagePlanAdded(
                _planId,
                _uninsureFees[i], 
                _insuranceFees[i], 
                _periodInMonths[i]
            );
        }
    }


    /**
     * @notice adds package plan
     * @param _periodInMonths the periods of the package in Months
     * @param _insuranceFee the insurance fee for the package in percentage
     * @param _uninsureFee the penalty amount for insurance cancellation
     */
    function addPackagePlan(
        uint8 _periodInMonths,
        uint8 _insuranceFee,
        uint _uninsureFee) external onlyOwner returns(bytes32){

        bytes32 _planId = keccak256(abi.encodePacked(
            _periodInMonths,
            _insuranceFee,
            _uninsureFee));
        
        require(!planExists(_planId), "Rance Protocol: PackagePlan already exists");

        planIdToPackagePlan[_planId] = PackagePlan(
            _planId,
            _periodInMonths, 
            _insuranceFee, 
            _uninsureFee,
            true
        );

        packagePlans.push(planIdToPackagePlan[_planId]); 


        emit PackagePlanAdded(
            _planId,
            _uninsureFee, 
            _insuranceFee, 
            _periodInMonths
        );

        return _planId;
    }


    /**
    @notice Method for adding payment token
    @dev Only admin
    @param _token ERC20 token address
    */
    function addPaymentToken(string memory _tokenName,address _token) external onlyOwner {
        require(!added[_token], "Rance Protocol:paymentToken already added");
        added[_token] = true;
        paymentTokenNameToAddress[_tokenName] = _token;
        noPaymentTokens += 1;
        IERC20Upgradeable(_token).approve(address(uniswapRouter), type(uint256).max);

        emit PaymentTokenAdded(_tokenName, _token);
    }

    /**
    @notice Method for removing payment token
    @dev Only admin
    @param _token ERC20 token address
    */
    function removePaymentToken(string memory _tokenName,address _token) external onlyOwner {
        require(added[_token], "Rance Protocol:paymentToken already added");
        added[_token] = false;
        paymentTokenNameToAddress[_tokenName] = _token;
        noPaymentTokens -= 1;
        IERC20Upgradeable(_token).approve(address(uniswapRouter), 0);

        emit PaymentTokenRemoved(_tokenName, _token);
    }


    /**
     * @notice get all package plans
     * @return packagePlans return array of package plans
     */
    function getAllPackagePlans() external view returns(PackagePlan[] memory){
        uint length = packagePlans.length;
        PackagePlan[] memory output = new PackagePlan[](length);
        uint index = 0;
        for (uint i = 0; i < length; i = i + 1) {
            if(packagePlans[i].isActivated == true){
                output[index] = packagePlans[i];
                index = index + 1;
            }
        }
        return packagePlans;
    }
    

    /**
     * @notice purchases an insurance package 
     * @param _planId      id of the package plan 
     * @param _amount the amount deposited
     * @param _insureCoin the insureCoin choosen by the user
     * @param _paymentTokenName the payment token deposited
     */
    function insure
    (
        bytes32 _planId,
        uint _amount,
        address _insureCoin,
        string memory _paymentTokenName) external{
        require(planIdToPackagePlan[_planId].isActivated, "Rance Protocol: PackagePlan not active");
        uint insureAmount = getInsureAmount(_planId, _amount);
        uint insuranceFee = _amount.sub(insureAmount);
        address paymentToken = paymentTokenNameToAddress[_paymentTokenName];

        IERC20Upgradeable(paymentToken).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20Upgradeable(paymentToken).approve(address(treasury), insuranceFee);
        IERC20Upgradeable(paymentToken).safeTransfer(address(treasury), insuranceFee);
        uint swapOutput = _swap(paymentToken, _insureCoin, msg.sender, insureAmount);

        totalInsuranceLocked += insureAmount;
        uint endTimestamp = (block.timestamp).add(uint(planIdToPackagePlan[_planId].periodInMonths).mul(30 days));

        planToUserPackage[_planId][msg.sender] = Package({
            user: msg.sender,
            planId: _planId,
            initialDeposit: insureAmount,
            insureOutput: swapOutput,
            startTimestamp: block.timestamp,
            endTimestamp: endTimestamp,
            isCancelled: false,
            isWithdrawn: false,
            insureCoin: _insureCoin,
            paymentToken: paymentToken
        });
        userToPlans[msg.sender].push(_planId);

        emit InsuranceActivated(
            _planId,
            msg.sender
        );
    }

    /**
     * @notice get all user packages
     * @return Package return array of user packages
     */
    function getAllUserPackages(address _user) external view returns(Package[] memory) {
        uint length = userToPlans[_user].length;
        Package[] memory output = new Package[](length);
        for(uint i = 0; i < length; i = i + 1){
            output[i] = planToUserPackage[userToPlans[_user][i]][_user];
        }
        
        return output;
    }

    /**
     * @notice cancel insurance package
     * @param _planId id of package plan to cancel
     */
    function cancel(bytes32 _planId) external nonReentrant{
        require(planExists(_planId), "Rance Protocol: PackagePlan does not exist");

        Package storage userPackage = planToUserPackage[_planId][msg.sender];
        require(isPackageActive(userPackage) && 
        !userPackage.isCancelled, "Rance Protocol: Package Not Cancellable");

        userPackage.isCancelled = true;
        userPackage.isWithdrawn = true;


        IERC20Upgradeable(userPackage.insureCoin).safeTransferFrom(
            msg.sender,
            address(treasury),
            userPackage.insureOutput
        );

        RANCE.safeTransferFrom(
            msg.sender,
            address(treasury), 
            planIdToPackagePlan[_planId].uninsureFee
        );

        treasury.withdrawToken(
            userPackage.paymentToken, 
            msg.sender, 
            userPackage.initialDeposit
        );     

       
        emit InsuranceCancelled(
            _planId, 
            msg.sender
        );
    }


    /**
     * @notice withdraw insurance package
     * @param _planId id of packagePlan to withdraw
     */
    function withdraw(bytes32 _planId) external nonReentrant{
        require(planExists(_planId), "Rance Protocol: PackagePlan does not exist");

        Package storage userPackage = planToUserPackage[_planId][msg.sender];
        require(!isPackageActive(userPackage) && 
        !userPackage.isWithdrawn && !userPackage.isCancelled,
         "Rance Protocol: Package Not Withdrawable");

        userPackage.isWithdrawn = true;

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
            _planId, 
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
     * @notice retrieves the package end date
     * @return endDate return the enddate of package
     */
    function retrievePackageEndDate(Package memory package) public view returns(uint) {

        return package.startTimestamp.add(uint(planIdToPackagePlan[package.planId].periodInMonths).mul(30 days));
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
        address _tokenA, 
        address _tokenB,
        address _to,
        uint _amount
    ) private returns(uint){
        uint deadline = block.timestamp;
        address[] memory path = new address[](2);
        path[0] = _tokenA;
        path[1] = _tokenB;
        uint amountOutMin = uniswapRouter.getAmountsOut(_amount, path)[1];
        uint[] memory amounts = uniswapRouter.swapExactTokensForTokens(_amount, amountOutMin, path, _to, deadline);

        return amounts[1];
    }


    function isPackageActive(Package memory package) public view returns(bool){
        return block.timestamp <= retrievePackageEndDate(package);
    }

}