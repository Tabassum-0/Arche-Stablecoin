// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title ARCEngine
 * @author Tabassum
 *
 * This system is designed to be as minimal as possible, and have the tokens
 * maintain a 1 token = 1 doller peg
 * This stablecoin hs the properties:
 * -Exogenous Collateral
 * -Doller Pegged
 * -Algorithmically Stable
 *
 * It is similar to DAI if DAI had no givernance,no fees, and was only backed
 * by wETH an wBTc
 *
 * Our ARC system should always be "overcollaterlized". At no point,should the
 * value of all collateral <= backed value of te ARC
 *
 * @notice This contract is the core of the ARC system.It handles all the logic
 * for minig and redeeming ARC, as well as depositing & withdrawing collateral.
 * @notice This contract is very loosely based on the makersDao DSS(DAI) system.
 *
 */
contract ARCEngine is ReentrancyGuard {
    ///////////////
    //  ERRORS  //
    //////////////

    error ARCEngine__NeedsMoreThanZero();
    error ARCEngine__TokenAddressesAndPrcieFeedAddressesMustBeSameLength();
    error ARCEngine__NotAllowedToken();
    error ARCEngine__TransferFailed();
    error ARCEngine__BreaksHealthFactor(uint256 healthFactor);
    error ARCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error ARCEngine__HealthFactorNotImproved();

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    using OracleLib for AggregatorV3Interface;

    //////////////////////////
    ////  STATE VARIABLE  ///
    /////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; //This means a 10% bonus

    mapping(address token => address priceFeed) private sPriceFeeds; //tokenPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private sCollateralDeposited;
    mapping(address user => uint256 amountArcMinted) private sArcMinted;

    address[] private sCollateralTokens;

    DecentralizedStableCoin private immutable I_ARC;

    ///////////////
    //  EVENTS  //
    //////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    ///////////////
    // MODIFIERS //
    //////////////

    modifier moreThanZero(uint256 amount) {
        _moreThanZero(amount);
        _;
    }

    modifier isAllowedToken(address token) {
        _isAllowedToken(token);
        _;
    }

    ///////////////
    // FUNCTIONS //
    //////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address arcAddress) {
        //USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert ARCEngine__TokenAddressesAndPrcieFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            sPriceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            sCollateralTokens.push(tokenAddresses[i]);
        }
        I_ARC = DecentralizedStableCoin(arcAddress);
    }

    /////////////////////////////
    ////  EXTERNAL FUNCTIONS  ///
    ////////////////////////////

    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountArcToMint The amouny of decentralized stablecoin to mint
     * @notice this function will deposit your collateral and mint ARC in one transaction
     */

    function depositCollateralAndMintArc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountArcToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintArc(amountArcToMint);
    }

    /**
     *@notice follows CEI
     * @param tokenCollateralAddress is the address of the token to deposit as collateral
     * @param amountCollateral is the amount of collateral to deposit
     */

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        sCollateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert ARCEngine__TransferFailed();
        }
    }

    /**
     *
     * @param tokenCollateralAddress The collateral address to redeem
     * @param amountCollateral The amount collateral to reedem
     * @param amountArcToBurn The amount of decentralized stablecoin to burn
     * This function burns ARC and redeems underlying collateral in one transaction
     */

    function redeemCollateralForArc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountArcToBurn)
        external
    {
        _burnArc(amountArcToBurn, msg.sender, msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    //CEI: Check, Effects, Interactions
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI
     * @param amountArcToMint is The amount of decentralized stablecoin to mint
     * @notice they must have more collateral value than the minimum thresehold
     */
    function mintArc(uint256 amountArcToMint) public moreThanZero(amountArcToMint) nonReentrant {
        sArcMinted[msg.sender] += amountArcToMint;

        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = I_ARC.mint(msg.sender, amountArcToMint);
        if (!minted) {
            revert ARCEngine__MintFailed();
        }
    }

    function burnArc(uint256 amount) public moreThanZero(amount) {
        _burnArc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param collateral The erc20 collateral address to liquidate from the user
     * @param user The user who has broken the health factor.Their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC you want to burn to improve the users health factor
     * @notice You can partially liquidate a user
     * @notice You will get a liquidate bonus fro taking the users funds
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in orde for this to work
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldnt be able to incentive the liquiditors
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     *
     * Follows CEI: Checks, Effects, Interactions
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        //Bad user: $140 ETH, $100 DSC
        //Debt to cover = $100

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnArc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert ARCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    ///////////////////////////////////////
    ///PRIVATE & INTERNAL VIEW FUNCTIONS///
    ///////////////////////////////////////

    /**
     * @dev low-level internal function, do not call unless the function calling it,
     * is checking for health factor being broken
     */
    function _burnArc(uint256 amountArcToBurn, address onBehalfOf, address arcFrom) private {
        sArcMinted[onBehalfOf] -= amountArcToBurn;
        bool success = I_ARC.transferFrom(arcFrom, address(this), amountArcToBurn);
        if (!success) {
            revert ARCEngine__TransferFailed();
        }
        I_ARC.burn(amountArcToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        sCollateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        //Calculate health factor
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert ARCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalArcMinted, uint256 collateralValueInUsd)
    {
        totalArcMinted = sArcMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalArcMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        if (totalArcMinted == 0) {
            return type(uint256).max;
        }
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalArcMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert ARCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _isAllowedToken(address token) internal view {
        if (sPriceFeeds[token] == address(0)) {
            revert ARCEngine__NotAllowedToken();
        }
    }

    function _moreThanZero(uint256 amount) internal pure {
        if (amount == 0) {
            revert ARCEngine__NeedsMoreThanZero();
        }
    }
    ///////////////////////////////////////
    /// PUBLIC & EXTERNAL VIEW FUNCTIONS //
    ///////////////////////////////////////

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(sPriceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < sCollateralTokens.length; i++) {
            address token = sCollateralTokens[i];
            uint256 amount = sCollateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(sPriceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        //1 ETH = 1000 doller
        //The returned value from CL will be 1000 * 1e8
        //1e8 = 1 * 10^8 = 100000000
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalArcMinted, uint256 collateralValueInUsd)
    {
        (totalArcMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return sCollateralDeposited[user][token];
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return sCollateralTokens;
    }

    function getArc() external view returns (address) {
        return address(I_ARC);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return sPriceFeeds[token];
    }
}
