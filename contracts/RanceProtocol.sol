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
        bytes32 packageId;
        uint initialDeposit; 
        uint startTimestamp;
        uint endTimestamp;
        bool active;
        bool isCancelled;
        bool isWithdrawn;
        address insureCoin;
        address paymentToken;
        PackagePlan packagePlan;
    }

    /**
     * @dev list of all packages purchased per user
     */
    mapping(address => Package[]) private userToPackages;

    /**
     *  @dev retrieve package plan with package plan id
     */
    mapping (bytes32 => PackagePlan) private idToPlan;

     /**
     *  @dev retrieve package with package id
     */
    mapping(bytes32 => Package) private idToPackage;

    /**
     *  @dev list all package plans
     */
    PackagePlan[] private packagePlans;

    /**
     * @dev Emitted when an insurance package is activated
     */
    event InsuranceActivated(
        bytes32 _planId,
        address _insureCoin,
        uint _amount,
        uint  _startTimestamp,
        uint _endTimestamp
    );


    /**
     * @dev Emitted when an insurance package is cancelled
     */
    event InsuranceCancelled(
        uint _amount,
        uint _penalty
    );


    /**
     * @dev Emitted when an insurance package is withdrawn
     */
    event InsuranceWithdrawn(uint _amount);

    /**
     * @dev Emitted when a package plan is updated
     */
    event PackagePlanUpdated(
        bytes32 _id,
        uint _uninsureFee,
        uint8 _insuranceFee,
        uint8 _periodInMonths
    );

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
         address _rance)
        public initializer { 
        __Ownable_init();
        treasury = IRanceTreasury(_treasuryAddress);
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        RANCE = IERC20Upgradeable(_rance);
        totalInsuranceLocked = 0;
        uint8[3] memory periodInMonths = [6,12,24];
        uint8[3] memory insuranceFees = [100, 50, 25];
        uint72[3] memory uninsureFees = [1 ether, 100 ether, 1000 ether];
        bytes32[3] memory ids = [
            keccak256(abi.encodePacked(periodInMonths[0],insuranceFees[0],uninsureFees[0])),
            keccak256(abi.encodePacked(periodInMonths[1],insuranceFees[1],uninsureFees[1])),
            keccak256(abi.encodePacked(periodInMonths[2],insuranceFees[2],uninsureFees[2]))
        ];
        for (uint i = 0; i < 3; i = i + 1 ) {
            packagePlans.push(idToPlan[ids[i]] =  PackagePlan(
                ids[i],
                periodInMonths[i],
                insuranceFees[i],
                uninsureFees[i]));
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
     * @param _planId the package plan id
     * @param _periodInMonths the periods of the package in Months
     * @param _insuranceFee the insurance fee for the package in percentage
     * @param _uninsureFee the penalty amount for insurance cancellation
     */
    function updatePackagePlan(
        bytes32 _planId,
        uint8 _periodInMonths,
        uint8 _insuranceFee,
        uint _uninsureFee) external{

        for (uint i = 0; i < packagePlans.length; i = i + 1 ) {
            if(packagePlans[i].planId == _planId){
                packagePlans[i] = idToPlan[_planId] = PackagePlan(
                    _planId,
                    _periodInMonths, 
                    _insuranceFee, 
                    _uninsureFee
                );
            }
        }

        emit PackagePlanUpdated(
            _planId,
            _uninsureFee, 
            _insuranceFee, 
            _periodInMonths
        );
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
        uint _uninsureFee) external{

        bytes32 _planId = keccak256(abi.encodePacked(
            _periodInMonths,
            _insuranceFee,
            _uninsureFee));

        packagePlans.push(idToPlan[_planId] = PackagePlan(
            _planId,
            _periodInMonths, 
            _insuranceFee, 
            _uninsureFee
            ));

        emit PackagePlanAdded(
            _planId,
            _uninsureFee, 
            _insuranceFee, 
            _periodInMonths
        );
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
     * @param _paymentToken the payment token deposited
     */
    function Insure
    (
        bytes32 _planId,
        uint _amount,
        address _insureCoin,
        address _paymentToken) external{

        uint insuranceFee = getInsuranceFee(_planId, _amount);
        uint insureAmount = _amount.sub(insuranceFee);

        IERC20Upgradeable(_paymentToken).safeTransferFrom(msg.sender, address(treasury), insuranceFee);

        _swap(_paymentToken, _insureCoin, msg.sender, insureAmount);

        totalInsuranceLocked += insureAmount;

        Package memory package;
        package.startTimestamp = block.timestamp;
        package.packagePlan = idToPlan[_planId];
        package.active = isPackageActive(package);
        package.endTimestamp = retrievePackageEndDate(package);
        package.initialDeposit = insureAmount;
        package.isWithdrawn = false;
        package.isCancelled = false;
        package.insureCoin = _insureCoin;
        package.paymentToken = _paymentToken;
        package.packageId = keccak256(abi.encodePacked(
            package.startTimestamp,
            package.endTimestamp,
            package.initialDeposit
        ));
        idToPackage[package.packageId] = package;
        userToPackages[msg.sender].push(package);
        

        emit InsuranceActivated(
            _planId, 
            _insureCoin,
            _amount, 
            block.timestamp,
            package.endTimestamp
        );
    }

    /**
     * @notice get all user packages
     * @return Package return array of user packages
     */
    function getUserPackages(address _user) external view returns(Package[] memory) {
        return userToPackages[_user];
    }

    /**
     * @notice cancel insurance package
     * @param packageId id of package to cancel
     */
    function cancel(bytes32 packageId) external nonReentrant{
        require(idToPackage[packageId].active && 
        !idToPackage[packageId].isCancelled);
        Package storage package = idToPackage[packageId];

        for (uint i = 0; i < userToPackages[msg.sender].length; i = i + 1 ) {
            if(userToPackages[msg.sender][i].packageId == packageId){
                package.isCancelled = userToPackages[msg.sender][i].isCancelled = true;
            }
        }

        RANCE.safeTransferFrom(
            msg.sender,
            address(treasury), 
            package.packagePlan.uninsureFee
        );

        treasury.withdrawToken(
            package.paymentToken, 
            msg.sender, 
            package.initialDeposit
        );     

        emit InsuranceCancelled(
            package.initialDeposit, 
            package.packagePlan.uninsureFee);   


    }


    /**
     * @notice withdraw insurance package
     * @param packageId id of package to withdraw
     */
    function withdraw(bytes32 packageId) external nonReentrant{
        require(!idToPackage[packageId].active && 
        !idToPackage[packageId].isWithdrawn);
        Package storage package = idToPackage[packageId];

        for (uint i = 0; i < userToPackages[msg.sender].length; i = i + 1 ) {
            if(userToPackages[msg.sender][i].packageId == packageId){
                package.isWithdrawn = userToPackages[msg.sender][i].isCancelled = true;
            }
        }

        treasury.withdrawToken(
            package.paymentToken, 
            msg.sender, 
            package.initialDeposit
        );     

        emit InsuranceWithdrawn(package.initialDeposit);
    } 

    /**
     * @notice get the calculated insurance fee
     * @param _planId id of the package plan
     * @param _amount amount to be calculate
     * @return insuranceFee return the insurance fee for specific period and amount
     */
    function getInsuranceFee(
        bytes32 _planId, 
        uint _amount) public view returns(uint){
        PackagePlan memory packagePlan = idToPlan[_planId];
        uint percentage = uint(packagePlan.insuranceFee).mul(100); 
        uint insuranceFee = ((percentage.div(2)).mul(_amount)).div(10000);
        return insuranceFee;
    }

    /**
     * @notice retrieves the package end date
     * @return endDate return the enddate of package
     */
    function retrievePackageEndDate(Package memory package) private pure returns(uint) {
        return package.startTimestamp + (package.packagePlan.periodInMonths * 30 days);
    }


    function _swap(
        address _tokenA, 
        address _tokenB,
        address _to,
        uint _amount
    ) private{
        uint deadline = block.timestamp;
        address[] memory path = getTokensPath(_tokenA, _tokenB);
        uint amountOutMin = uniswapRouter.getAmountsOut(_amount, path)[1];
        IERC20Upgradeable(_tokenA).transferFrom(msg.sender, address(this), _amount);
        IERC20Upgradeable(_tokenA).approve(address(uniswapRouter), _amount);
        uniswapRouter.swapExactTokensForTokens(_amount, amountOutMin, path, _to, deadline);
    }

    function getTokensPath(address tokenA, address tokenB) private pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = tokenA;
        path[1] = tokenB;
        return path;
    }

    function isPackageActive(Package memory package) private view returns(bool){
        return block.timestamp <= retrievePackageEndDate(package);
    }

}