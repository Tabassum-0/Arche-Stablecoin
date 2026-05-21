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
// receive function (if exists)
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
    error ARCEngine__transferFailed();
    error ARCEngine__BreaksHealthFactor(uint256 healthFactor);
    error ARCEngine__MintFailed();

    //////////////////////////
    ////  STATE VARIABLE  ///
    /////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private sPriceFeeds; //tokenPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private sCollateralDeposited;
    mapping(address user => uint256 amountArcMinted) private sArcMinted;
    address[] private sCollateralToken;

    DecentralizedStableCoin private immutable iArc;

    ///////////////
    //  EVENTS  //
    //////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

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
            sCollateralToken.push(tokenAddresses[i]);
        }
        iArc = DecentralizedStableCoin(arcAddress);
    }

    /////////////////////////////
    ////  EXTERNAL FUNCTIONS  ///
    ////////////////////////////

    function depositCollateralAndMintArc() external {}

    /**
     *@notice follows CEI
     * @param tokenCollateralAddress is the address of the token to deposit as collateral
     * @param amountCollateral is the amount of collateral to deposit
     */

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        sCollateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert ARCEngine__transferFailed();
        }
    }

    function redeemCollateralForArc() external {}

    function redeemCollateral() external {}

    /**
     * @notice follows CEI
     * @param amountArcToMint is The amount of decentralized stablecoin to mint
     * @notice they must have more collateral value than the minimum thresehold
     */
    function mintArc(uint256 amountArcToMint) external moreThanZero(amountArcToMint) nonReentrant {
        sArcMinted[msg.sender] += amountArcToMint;

        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = iArc.mint(msg.sender, amountArcToMint);
        if (!minted) {
            revert ARCEngine__MintFailed();
        }
    }

    function burnArc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    ///////////////////////////////////////
    ///PRIVATE & INTERNAL VIEW FUNCTIONS///
    ///////////////////////////////////////
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

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < sCollateralToken.length; i++) {
            address token = sCollateralToken[i];
            uint256 amount = sCollateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(sPriceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        //1 ETH = 1000 doller
        //The returned value from CL will be 1000 * 1e8
        //1e8 = 1 * 10^8 = 100000000
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
