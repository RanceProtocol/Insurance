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
     * @dev data of Package Plan on the Insurance Protocol
     */
    struct PackagePlan {
        bytes32 planId;
        uint8 periodInMonths;
        uint8 insuranceFee;
        uint uninsureFee; 
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
     *  @dev retrieve packagePlan index with packagePlan id
     */
    mapping (bytes32 => uint) public planIdToIndex;

     /**
     *  @dev retrieve user package with packagePlan id
     */
    mapping(bytes32 => mapping(address => Package)) public planToUserPackage;

    /**
     * @dev retrieve payment token index  with name
     */
    mapping(string => uint) public paymentTokenNameToIndex;


    /**
     * @dev check if payment token is added
     */
    mapping(address => bool) public added;

    /**
     *  @dev list all package plans
     */
    PackagePlan[] public packagePlans;

    /**
     *  @dev list all payment tokens
     */
    address[] public paymentTokens;


    /**
     * @dev Emitted when an insurance package is activated
     */
    event InsuranceActivated(
        bytes32 _planId,
        address _user,
        address _insureCoin,
        address _paymentToken,
        uint _amount,
        uint _endTimestamp
    );


    /**
     * @dev Emitted when an insurance package is cancelled
     */
    event InsuranceCancelled(
        address indexed _user,
        uint _amount,
        uint _penalty
    );

    /**
     * @dev Emitted when a payment token is added
     */
    event PaymentTokenAdded(uint index, address indexed paymentToken);


    /**
     * @dev Emitted when an insurance package is withdrawn
     */
    event InsuranceWithdrawn(address indexed _user,uint _amount);

    /**
     * @dev Emitted when a package plan is updated
     */
    event PackagePlanUpdated(bytes32 _id);

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
        paymentTokens.push(_paymentToken);
        uint index = paymentTokens.length - 1;
        paymentTokenNameToIndex["MUSD"] = index + 1;
        uint8[3] memory periodInMonths = [6,12,24];
        uint8[3] memory insuranceFees = [100, 50, 25];
        uint72[3] memory uninsureFees = [1 ether, 10 ether, 100 ether];
        bytes32[3] memory ids = [
            keccak256(abi.encodePacked(periodInMonths[0],insuranceFees[0],uninsureFees[0])),
            keccak256(abi.encodePacked(periodInMonths[1],insuranceFees[1],uninsureFees[1])),
            keccak256(abi.encodePacked(periodInMonths[2],insuranceFees[2],uninsureFees[2]))
        ];
        for (uint i = 0; i < 3; i = i + 1 ) {
            packagePlans.push(PackagePlan(
                ids[i],
                periodInMonths[i],
                insuranceFees[i],
                uninsureFees[i]));
            uint newIndex = packagePlans.length - 1;
            planIdToIndex[ids[i]] = newIndex + 1;
        }

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
            uint index = _getPlanIndex(_planIds[i]);
            PackagePlan storage packagePlan = packagePlans[index];
            packagePlan.planId = _planIds[i];
            packagePlan.periodInMonths = _periodInMonths[i];
            packagePlan.insuranceFee = _insuranceFees[i];
            packagePlan.uninsureFee = _uninsureFees[i];

            emit PackagePlanUpdated(_planIds[i]);
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

        packagePlans.push(PackagePlan(
            _planId,
            _periodInMonths, 
            _insuranceFee, 
            _uninsureFee
            ));

        uint newIndex = packagePlans.length - 1;
        planIdToIndex[_planId] = newIndex + 1;

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
        paymentTokens.push(_token);
        uint index = paymentTokens.length - 1;
        paymentTokenNameToIndex[_tokenName] = index + 1;
        emit PaymentTokenAdded(index, _token);
    }


    /**
     * @notice get all package plans
     * @return packagePlans return array of package plans
     */
    function getAllPackagePlans() external view returns(PackagePlan[] memory){
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

        uint insureAmount = getInsureAmount(_planId, _amount);
        uint insuranceFee = _amount.sub(insureAmount);
        uint index = _getPlanIndex(_planId);
        uint payTokenIndex = paymentTokenNameToIndex[_paymentTokenName];

        IERC20Upgradeable(paymentTokens[payTokenIndex]).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20Upgradeable(paymentTokens[payTokenIndex]).approve(address(treasury), insuranceFee);
        IERC20Upgradeable(paymentTokens[payTokenIndex]).safeTransfer(address(treasury), insuranceFee);
        uint swapOutput = _swap(paymentTokens[payTokenIndex], _insureCoin, msg.sender, insureAmount);

        totalInsuranceLocked += insureAmount;

        planToUserPackage[_planId][msg.sender] = Package(
            msg.sender,
            _planId,
            block.timestamp,
            (block.timestamp).add(uint(packagePlans[index].periodInMonths).mul(30 days)),
            insureAmount,
            swapOutput,
            false,
            false,
            _insureCoin,
            paymentTokens[payTokenIndex]
        );
        userToPlans[msg.sender].push(_planId);

        emit InsuranceActivated(
            _planId,
            msg.sender,
            _insureCoin,
            paymentTokens[payTokenIndex],
            insureAmount, 
            (block.timestamp).add(uint(packagePlans[index].periodInMonths).mul(30 days))
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

        uint index = _getPlanIndex(_planId);



        IERC20Upgradeable(userPackage.insureCoin).safeTransferFrom(
            msg.sender,
            address(treasury),
            userPackage.insureOutput
        );

        RANCE.safeTransferFrom(
            msg.sender,
            address(treasury), 
            packagePlans[index].uninsureFee
        );

        treasury.withdrawToken(
            userPackage.paymentToken, 
            msg.sender, 
            userPackage.initialDeposit
        );     

        emit InsuranceCancelled(
            msg.sender,
            userPackage.initialDeposit, 
            packagePlans[index].uninsureFee);   
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

        emit InsuranceWithdrawn(msg.sender, userPackage.initialDeposit);
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
        uint index = _getPlanIndex(_planId);
        PackagePlan memory packagePlan = packagePlans[index];
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
        uint index = _getPlanIndex(package.planId);
        return package.startTimestamp.add(uint(packagePlans[index].periodInMonths).mul(30 days));
    }

    /**
     * @notice Determines whether a package exists with the given id
     * @param _planId the id of a package plan
     * @return true if package plan exists and its id is valid
     */
    function planExists(bytes32 _planId)
        private view returns (bool){
        if (packagePlans.length == 0) {
            return false;
        }

        uint index = planIdToIndex[_planId];
        return (index > 0);
    }

    /**
     * @notice Returns the array index of the package plan with the given id
     * @dev if the event id is invalid, then the return value will be incorrect 
     * and may cause error; 
     * @param _planId the package plan id to get
     * @return the array index of this event.
     */
    function _getPlanIndex(bytes32 _planId)
        private view
        returns (uint)
    {
        //check if the event exists
        require(planExists(_planId), "Rance Protocol: PackagePlan does not exist");

        return planIdToIndex[_planId] - 1;
    }


    function _swap(
        address _tokenA, 
        address _tokenB,
        address _to,
        uint _amount
    ) private returns(uint){
        uint deadline = block.timestamp;
        address[] memory path = getTokensPath(_tokenA, _tokenB);
        uint amountOutMin = uniswapRouter.getAmountsOut(_amount, path)[1];
        IERC20Upgradeable(_tokenA).approve(address(uniswapRouter), _amount);
        uint[] memory amounts = uniswapRouter.swapExactTokensForTokens(_amount, amountOutMin, path, _to, deadline);

        return amounts[1];
    }

    function getTokensPath(address tokenA, address tokenB) private pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = tokenA;
        path[1] = tokenB;
        return path;
    }

    function isPackageActive(Package memory package) public view returns(bool){
        return block.timestamp <= retrievePackageEndDate(package);
    }

}