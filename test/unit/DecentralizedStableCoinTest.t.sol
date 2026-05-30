//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployARC} from "../../script/DeployARC.s.sol";
import {ARCEngine} from "../../src/ARCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../test/mocks/ERC20Mock.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    DeployARC deployer;
    DecentralizedStableCoin arc;
    HelperConfig config;
    ARCEngine engine;

    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_ARC_TO_MINT = 100e18;

    function setUp() public {
        deployer = new DeployARC();
        (arc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
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

    // ── Only owner can mint ──
    function testOnlyOwnerCanMintArcToken() public {
        vm.startPrank(USER);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        arc.mint(USER, AMOUNT_ARC_TO_MINT);
        vm.stopPrank();
    }

    // ── Mint to zero address reverts ──
    function testMintRevertsIfToIsZeroAddress() public {
        address owner = arc.owner();
        vm.startPrank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__NotZeroAddress.selector);
        arc.mint(address(0), AMOUNT_ARC_TO_MINT);
        vm.stopPrank();
    }

    // ── Mint zero amount reverts ──
    function testMintRevertsIfAmountIsZero() public {
        address owner = arc.owner();
        vm.startPrank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        arc.mint(USER, 0);
        vm.stopPrank();
    }

    // ── Only owner can burn ──
    function testOnlyOwnerCanBurnArcToken() public depositedCollateralAndMintedArc {
        vm.startPrank(USER);
        vm.expectRevert();
        arc.burn(AMOUNT_ARC_TO_MINT);
        vm.stopPrank();
    }

    // ── Burn zero amount reverts ──
    function testBurnRevertsIfAmountIsZero() public {
        address owner = arc.owner();
        vm.startPrank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        arc.burn(0);
        vm.stopPrank();
    }

    // ── Burn more than balance reverts ──
    function testBurnRevertsIfAmountExceedsBalance() public {
        address owner = arc.owner();
        // owner has 0 balance but tries to burn 1 token
        vm.startPrank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        arc.burn(1e18);
        vm.stopPrank();
    }

    // ── Mint returns true ──
    function testMintReturnsTrue() public {
        address owner = arc.owner();
        vm.prank(owner);
        bool result = arc.mint(USER, 1e18);
        assertTrue(result);
    }
}
