// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

// import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/SafeERC20.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/math/SafeMath.sol";

contract NordTokenVesting is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event DistributionAdded(address indexed investor, address indexed caller, uint256 allocation);

    event DistributionRemoved(address indexed investor, address indexed caller, uint256 allocation);

    event WithdrawnTokens(address indexed investor, uint256 value);

    event RecoverToken(address indexed token, uint256 indexed amount);

    enum DistributionType { ECOSYSTEM, FOUNDATION, TEAM, ADVISORS }

    uint256 private totalAllocatedAmount;
    uint256 private initialTimestamp;
    IERC20 private nord;

    struct Distribution {
        address beneficiary;
        bool hasCliff;
        uint256 withdrawnTokens;
        uint256 tokensAllotment;
        uint256 vestingMonths;
        DistributionType distributionType;
    }

    mapping(DistributionType => Distribution) public distibutionInfo;

    /// @dev Boolean variable that indicates whether the contract was initialized.
    bool public isInitialized = false;
    /// @dev Boolean variable that indicates whether the investors set was finalized.
    bool public isFinalized = false;

    address tressuryAddresss = 0x8bAbB21d4e55d51A475740e768fe0eECC09A93Fd;

    uint256 SCALING_FACTOR = 10**18; // decimals
    uint256 year = 365 days;
    uint256 oneMonth = year.div(12);
    uint256 cliff = oneMonth.mul(6);
    uint256 thirtySix = 36;
    uint256 twentyFour = 24;
    uint256 twelve = 12;

    /// @dev Checks that the contract is initialized.
    modifier initialized() {
        require(isInitialized, "not initialized");
        _;
    }

    /// @dev Checks that the contract is initialized.
    modifier notInitialized() {
        require(!isInitialized, "initialized");
        _;
    }

    constructor(address _token) {
        require(address(_token) != address(0x0), "Nord token address is not valid");
        nord = IERC20(_token);

        addDistribution(tressuryAddresss, DistributionType.ECOSYSTEM, 3500000 * SCALING_FACTOR, false, thirtySix);

        addDistribution(tressuryAddresss, DistributionType.FOUNDATION, 1500000 * SCALING_FACTOR, false, twentyFour);

        addDistribution(tressuryAddresss, DistributionType.TEAM, 2000000 * SCALING_FACTOR, true, twelve);

        addDistribution(tressuryAddresss, DistributionType.ADVISORS, 500000 * SCALING_FACTOR, true, twelve);
    }

    function getInitialTimestamp() public view returns (uint256 timestamp) {
        return initialTimestamp;
    }

    /// @dev Adds Distribution. This function doesn't limit max gas consumption,
    /// so adding too many investors can cause it to reach the out-of-gas error.
    /// @param _beneficiary The address of distribution.
    /// @param _tokensAllotment The amounts of the tokens that belong to each investor.
    function addDistribution(
        address _beneficiary,
        DistributionType _distributionType,
        uint256 _tokensAllotment,
        bool _hasCliff,
        uint256 _vestingMonths
    ) internal onlyOwner {
        require(_beneficiary != address(0), "Invalid address");
        require(_tokensAllotment > 0, "the investor allocation must be more than 0");
        Distribution storage distribution = distibutionInfo[_distributionType];

        require(distribution.tokensAllotment == 0, "investor already added");

        distribution.beneficiary = _beneficiary;
        distribution.tokensAllotment = _tokensAllotment;
        distribution.distributionType = _distributionType;
        distribution.hasCliff = _hasCliff;
        distribution.vestingMonths = _vestingMonths;

        emit DistributionAdded(_beneficiary, _msgSender(), _tokensAllotment);
    }

    function withdrawTokens(uint256 distributionType) external onlyOwner() initialized() {
        Distribution storage distribution = distibutionInfo[DistributionType(distributionType)];

        uint256 tokensAvailable = withdrawableTokens(DistributionType(distributionType));

        require(tokensAvailable > 0, "no tokens available for withdrawl");

        distribution.withdrawnTokens = distribution.withdrawnTokens.add(tokensAvailable);
        nord.safeTransfer(distribution.beneficiary, tokensAvailable);

        emit WithdrawnTokens(_msgSender(), tokensAvailable);
    }

    /// @dev The starting time of TGE
    /// @param _timestamp The initial timestamp, this timestap should be used for vesting
    function setInitialTimestamp(uint256 _timestamp) external onlyOwner() notInitialized() {
        isInitialized = true;
        initialTimestamp = _timestamp;
    }

    function withdrawableTokens(DistributionType distributionType) public view returns (uint256 tokens) {
        Distribution storage distribution = distibutionInfo[distributionType];
        uint256 availablePercentage = _calculateAvailablePercentage(distributionType);
        // console.log("Available Percentage: %s", availablePercentage);
        uint256 noOfTokens = _calculatePercentage(distribution.tokensAllotment, availablePercentage);
        uint256 tokensAvailable = noOfTokens.sub(distribution.withdrawnTokens);

        // console.log("Withdrawable Tokens: %s",  tokensAvailable);

        return tokensAvailable;
    }

    function _calculatePercentage(uint256 _amount, uint256 _percentage) private pure returns (uint256 percentage) {
        return _amount.mul(_percentage).div(100).div(1e18);
    }

    function _calculateAvailablePercentage(DistributionType distributionType)
        private
        view
        returns (uint256 availablePercentage)
    {
        // ECOSYSTEM has 36 months of linear monthly vesting
        // TEAM has 18 months of monthly vesting with 6 months of cliff
        // ECOSYSTEM monthly release = 100 / 36 = 2.777777778% percentage release every month
        Distribution storage distribution = distibutionInfo[distributionType];
        uint256 currentTimeStamp = block.timestamp;

        uint256 everyMonthReleasePercentage = uint256(100).mul(1e18).div(distribution.vestingMonths);

        uint256 noOfDays = (currentTimeStamp.sub(initialTimestamp)).div(60).div(60).div(24);
        // console.log("No of Days: %s ", noOfDays);
        // console.log("Month Percentage: %s", everyMonthReleasePercentage.mul(1));
        if (!distribution.hasCliff && noOfDays > 0 && noOfDays < 30) {
            return everyMonthReleasePercentage.mul(1);
        } else {
            // console.log("Month Percentage: %s", everyMonthReleasePercentage.mul(1));
            uint256 monthsSinceInitial = noOfDays.div(30);
            // console.log(monthsSinceInitial);
            if (distribution.hasCliff) {
                if (monthsSinceInitial >= 6) {
                    return everyMonthReleasePercentage.mul(monthsSinceInitial.sub(5));
                } else {
                    return 0;
                }
            } else if (monthsSinceInitial < distribution.vestingMonths) {
                return everyMonthReleasePercentage.mul(monthsSinceInitial.add(1));
            } else {
                return uint256(100).mul(1e18);
            }
        }
    }

    function recoverExcessToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(_msgSender(), amount);
        emit RecoverToken(token, amount);
    }
}
