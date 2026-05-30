//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployARC} from "../../script/DeployARC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ARCEngine} from "../../src/ARCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../test/mocks/ERC20Mock.sol";

contract ARCEngineTest is Test {
    DeployARC deployer;
    DecentralizedStableCoin arc;
    ARCEngine engine;
    HelperConfig config;

    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_ARC_TO_MINT = 100e18;

    function setUp() public {
        deployer = new DeployARC();
        (arc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, 100 ether); //extra for liquidation tests
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintedArc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintArc(weth, AMOUNT_COLLATERAL, AMOUNT_ARC_TO_MINT);
        vm.stopPrank();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeed() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(ARCEngine.ARCEngine__TokenAddressesAndPrcieFeedAddressesMustBeSameLength.selector);
        new ARCEngine(tokenAddresses, priceFeedAddresses, address(arc));
    }

    function testConstructorSetsCollateralTokens() public view {
        // Both weth and wbtc should be registered (via HelperConfig)
        // getUsdValue works only for allowed tokens — using it as a proxy check
        uint256 val = engine.getUsdValue(weth, 1e18);
        assertGt(val, 0);
    }

    ///////////////////////
    ////  PRICE TESTS  ///
    //////////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        //15e8 * 2000/ETH = 30000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    function testGetUsdValueZeroAmount() public view {
        // Zero amount should return zero
        assertEq(engine.getUsdValue(weth, 0), 0);
    }

    ///////////////////////////////////
    ////  DEPOSIT COLLATERAL TESTS  ///
    ///////////////////////////////////

    // ── Error: ARCEngine__NeedsMoreThanZero ──//
    function testConvertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(ARCEngine.ARCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    // ── Error: ARCEngine__NotAllowedToken ──//
    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("Ran", "Ran", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(ARCEngine.ARCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
    }

    // ── Error: ARCEngine__TransferFailed (no approval) ──
    function testRevertsDepositCollateralWithoutApproval() public {
        vm.startPrank(USER);
        // intentionally no approve() call
        vm.expectRevert(); // ERC20 transferFrom reverts on insufficient allowance
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    // ── Happy path: state update ──
    function testCanDepositcollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalArcMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);

        uint256 expectedTotalArcMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalArcMinted, expectedTotalArcMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    // ── Event: CollateralDeposited ──
    function testEmitsCollateralDepositedEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectEmit(true, true, true, true);
        emit ARCEngine.CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    // ── Multiple deposits accumulate ──
    function testMultipleDepositsAccumulate() public {
        uint256 half = AMOUNT_COLLATERAL / 2;

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, half);
        engine.depositCollateral(weth, half);
        vm.stopPrank();

        (, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 deposited = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(deposited, AMOUNT_COLLATERAL);
    }

    /*//////////////////////////////////////////////////////////////
                        MINT ARC TESTS
    //////////////////////////////////////////////////////////////*/

    // ── Error: ARCEngine__NeedsMoreThanZero ──
    function testRevertsIfMintAmountIsZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(ARCEngine.ARCEngine__NeedsMoreThanZero.selector);
        engine.mintArc(0);
        vm.stopPrank();
    }

    // ── Error: ARCEngine__BreaksHealthFactor (over-mint) ──
    function testRevertsIfMintBreaksHealthFactor() public depositedCollateral {
        // 10 ETH * $2000 = $20 000 collateral
        // With 50% threshold effective collateral = $10 000
        // Minting $10 001 must break health factor
        uint256 amountToMint = 10001e18;

        vm.startPrank(USER);
        vm.expectRevert();
        engine.mintArc(amountToMint);
        vm.stopPrank();
    }

    // ── Happy path ──
    function testCanMintArc() public depositedCollateral {
        vm.startPrank(USER);
        engine.mintArc(AMOUNT_ARC_TO_MINT);
        vm.stopPrank();

        (uint256 totalArcMinted,) = engine.getAccountInformation(USER);
        assertEq(totalArcMinted, AMOUNT_ARC_TO_MINT);
        // ARC token balance
        assertEq(arc.balanceOf(USER), AMOUNT_ARC_TO_MINT);
    }

    // ── Minting right at the boundary should succeed ──
    function testMintAtMaxDoesNotRevert() public depositedCollateral {
        // $10 000 exactly is the max (50% of $20 000 collateral)
        uint256 maxMint = 10_000e18;

        vm.startPrank(USER);
        engine.mintArc(maxMint);
        vm.stopPrank();

        (uint256 totalArcMinted,) = engine.getAccountInformation(USER);
        assertEq(totalArcMinted, maxMint);
    }

    /*//////////////////////////////////////////////////////////////
                DEPOSIT COLLATERAL AND MINT ARC TESTS
    //////////////////////////////////////////////////////////////*/

    function testDepositCollateralAndMintArcUpdatesState() public depositedCollateralAndMintedArc {
        (uint256 totalArcMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);

        assertEq(totalArcMinted, AMOUNT_ARC_TO_MINT);
        uint256 deposited = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(deposited, AMOUNT_COLLATERAL);
    }

    function testDepositCollateralAndMintArcRevertsIfHealthFactorBreaks() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert();
        // Try to mint far more than collateral allows
        engine.depositCollateralAndMintArc(weth, AMOUNT_COLLATERAL, 100_000e18);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        BURN ARC TESTS
    //////////////////////////////////////////////////////////////*/

    // ── Error: ARCEngine__NeedsMoreThanZero ──
    function testRevertsIfBurnAmountIsZero() public depositedCollateralAndMintedArc {
        vm.startPrank(USER);
        vm.expectRevert(ARCEngine.ARCEngine__NeedsMoreThanZero.selector);
        engine.burnArc(0);
        vm.stopPrank();
    }

    // ── Burn more than minted should underflow/revert ──
    function testRevertsIfBurnMoreThanMinted() public depositedCollateralAndMintedArc {
        vm.startPrank(USER);
        arc.approve(address(engine), AMOUNT_ARC_TO_MINT + 1);
        vm.expectRevert(); // arithmetic underflow on sArcMinted
        engine.burnArc(AMOUNT_ARC_TO_MINT + 1);
        vm.stopPrank();
    }

    // ── Happy path: full burn ──
    function testCanBurnArcFully() public depositedCollateralAndMintedArc {
        vm.startPrank(USER);
        arc.approve(address(engine), AMOUNT_ARC_TO_MINT);
        engine.burnArc(AMOUNT_ARC_TO_MINT);
        vm.stopPrank();

        (uint256 totalArcMinted,) = engine.getAccountInformation(USER);
        assertEq(totalArcMinted, 0);
        assertEq(arc.balanceOf(USER), 0);
    }

    // ── Happy path: partial burn ──
    function testCanBurnArcPartially() public depositedCollateralAndMintedArc {
        uint256 burnAmount = AMOUNT_ARC_TO_MINT / 2;

        vm.startPrank(USER);
        arc.approve(address(engine), burnAmount);
        engine.burnArc(burnAmount);
        vm.stopPrank();

        (uint256 totalArcMinted,) = engine.getAccountInformation(USER);
        assertEq(totalArcMinted, AMOUNT_ARC_TO_MINT - burnAmount);
    }

    // ── Burn without token approval should revert ──
    function testBurnRevertsWithoutApproval() public depositedCollateralAndMintedArc {
        vm.startPrank(USER);
        // no arc.approve()
        vm.expectRevert();
        engine.burnArc(AMOUNT_ARC_TO_MINT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    REDEEM COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/

    // ── Error: ARCEngine__NeedsMoreThanZero ──//
    function testRevertsIfRedeemAmountIsZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(ARCEngine.ARCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    // ── Error: breaks health factor on redeem ──//
    function testRevertsRedeemCollateralIfHealthFactorBreaks() public depositedCollateralAndMintedArc {
        // User has $100 ARC minted; redeeming all collateral should break health factor
        vm.startPrank(USER);
        vm.expectRevert();
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    // ── Happy path: full redeem after no minting ──//
    function testCanRedeemCollateralFully() public depositedCollateral {
        uint256 balanceBefore = ERC20Mock(weth).balanceOf(USER);

        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 balanceAfter = ERC20Mock(weth).balanceOf(USER);
        assertEq(balanceAfter, balanceBefore + AMOUNT_COLLATERAL);
    }

    // ── Event: CollateralRedeemed ──//
    function testEmitsCollateralRedeemedEvent() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectEmit(true, true, true, true);
        emit ARCEngine.CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    // ── Redeem more than deposited should underflow/revert ──
    function testRevertsRedeemMoreThanDeposited() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(); // arithmetic underflow
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL + 1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
            REDEEM COLLATERAL FOR ARC TESTS
    //////////////////////////////////////////////////////////////*/

    function testRedeemCollateralForArcBurnsAndRedeems() public depositedCollateralAndMintedArc {
        uint256 wethBalanceBefore = ERC20Mock(weth).balanceOf(USER);

        vm.startPrank(USER);
        arc.approve(address(engine), AMOUNT_ARC_TO_MINT);
        engine.redeemCollateralForArc(weth, AMOUNT_COLLATERAL, AMOUNT_ARC_TO_MINT);
        vm.stopPrank();

        (uint256 totalArcMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        assertEq(totalArcMinted, 0);
        assertEq(collateralValueInUsd, 0);
        assertEq(ERC20Mock(weth).balanceOf(USER), wethBalanceBefore + AMOUNT_COLLATERAL);
    }
}
