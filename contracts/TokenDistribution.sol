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

contract TokenDistribution is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event InvestorAdded(address indexed investor, address indexed caller, uint256 allocation);

    event InvestorRemoved(address indexed investor, address indexed caller, uint256 allocation);

    event WithdrawnTokens(address indexed investor, uint256 value);

    event DepositInvestment(address indexed investor, uint256 value);

    event TransferInvestment(address indexed owner, uint256 value);

    event RecoverToken(address indexed token, uint256 indexed amount);

    uint256 private totalAllocatedAmount;
    uint256 private initialTimestamp;
    IERC20 private usdt;
    IERC20 private nord;

    struct Investor {
        bool exists;
        uint256 withdrawnTokens;
        uint256 tokensAllotment;
    }

    mapping(address => Investor) public investorsInfo;

    /// @dev Boolean variable that indicates whether the contract was initialized.
    bool public isInitialized = false;
    /// @dev Boolean variable that indicates whether the investors set was finalized.
    bool public isFinalized = false;

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

    modifier onlyInvestor() {
        require(investorsInfo[_msgSender()].exists, "Only investors allowed");
        _;
    }

    constructor(address _nord) {
        nord = IERC20(_nord);
    }

    function getInitialTimestamp() public view returns (uint256 timestamp) {
        return initialTimestamp;
    }

    /// @dev Adds investor. This function doesn't limit max gas consumption,
    /// so adding too many investors can cause it to reach the out-of-gas error.
    /// @param _investor The addresses of new investors.
    /// @param _tokensAllotment The amounts of the tokens that belong to each investor.
    function addInvestor(address _investor, uint256 _tokensAllotment) external onlyOwner {
        require(_investor != address(0), "Invalid address");
        require(_tokensAllotment > 0, "the investor allocation must be more than 0");
        Investor storage investor = investorsInfo[_investor];

        require(investor.tokensAllotment == 0, "investor already added");

        investor.tokensAllotment = _tokensAllotment;
        investor.exists = true;
        totalAllocatedAmount = totalAllocatedAmount.add(_tokensAllotment);
        emit InvestorAdded(_investor, _msgSender(), _tokensAllotment);
    }

    /// @dev Removes investor. This function doesn't limit max gas consumption,
    /// so having too many investors can cause it to reach the out-of-gas error.
    /// @param _investor Investor address.
    function removeInvestor(address _investor) external onlyOwner() {
        require(_investor != address(0), "invalid address");
        Investor storage investor = investorsInfo[_investor];
        uint256 allocation = investor.tokensAllotment;
        require(allocation > 0, "the investor doesn't exist");

        totalAllocatedAmount = totalAllocatedAmount.sub(allocation);
        investor.exists = false;
        investor.tokensAllotment = 0;

        emit InvestorRemoved(_investor, _msgSender(), allocation);
    }

    // 15% on listing and rest daily distribution from day 31 for 11 months (12 months)
    function withdrawTokens() external onlyInvestor() initialized() {
        Investor storage investor = investorsInfo[_msgSender()];

        uint256 tokensAvailable = withdrawableTokens(_msgSender());

        require(tokensAvailable > 0, "no tokens available for withdrawl");

        investor.withdrawnTokens = investor.withdrawnTokens.add(tokensAvailable);
        nord.safeTransfer(_msgSender(), tokensAvailable);

        emit WithdrawnTokens(_msgSender(), tokensAvailable);
    }

    /// @dev The starting time of TGE
    /// @param _timestamp The initial timestamp, this timestap should be used for vesting
    function setInitialTimestamp(uint256 _timestamp) external onlyOwner() notInitialized() {
        isInitialized = true;
        initialTimestamp = _timestamp;
    }

    function withdrawableTokens(address _investor) public view returns (uint256 tokens) {
        Investor storage investor = investorsInfo[_investor];
        uint256 availablePercentage = _calculateAvailablePercentage();
        uint256 noOfTokens = _calculatePercentage(investor.tokensAllotment, availablePercentage);
        uint256 tokensAvailable = noOfTokens.sub(investor.withdrawnTokens);

        return tokensAvailable;
    }

    function _calculatePercentage(uint256 _amount, uint256 _percentage) private pure returns (uint256 percentage) {
        return _amount.mul(_percentage).div(100).div(1e18);
    }

    function _calculateAvailablePercentage() private view returns (uint256 availablePercentage) {
        // 15% on listing and rest daily distribution from day 31 for 11 months (12 months)

        // 1000000 NORD assigned
        // 15000 tokens on TGE - 15% on TGE
        // 85000 tokens distributed for 334 days - 85% remaining
        // 85000/334 = 254.491017964 tokens per day
        // 85/334 = 0.254491018% every day released

        uint256 thirtyOneDays = initialTimestamp + 31 days;
        uint256 oneYear = initialTimestamp + 365 days;
        uint256 remainingDistroPercentage = 85;
        uint256 noOfRemaingDays = 334;
        uint256 everyDayReleasePercentage = remainingDistroPercentage.mul(1e18).div(noOfRemaingDays);

        uint256 currentTimeStamp = block.timestamp;

        if (currentTimeStamp > initialTimestamp) {
            if (currentTimeStamp <= thirtyOneDays) {
                return uint256(15).mul(1e18);
            } else if (currentTimeStamp > thirtyOneDays && currentTimeStamp < oneYear) {
                // Date difference in days - (endDate - startDate) / 60 / 60 / 24; // 40 days

                uint256 noOfDays = (currentTimeStamp.sub(thirtyOneDays)).mul(1e18).div(60).div(60).div(24);
                uint256 currentUnlockedPercentage = noOfDays.mul(everyDayReleasePercentage).div(1e18);

                return uint256(15).mul(1e18).add(currentUnlockedPercentage);
            } else {
                return uint256(100).mul(1e18);
            }
        }
    }

    function recoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(_msgSender(), amount);
        emit RecoverToken(token, amount);
    }
}
