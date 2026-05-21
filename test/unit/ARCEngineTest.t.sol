//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployARC} from "../../script/DeployARC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ARCEngine} from "../../src/ARCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../test/mocks/ERC20Mock.sol";

contract ARCEngineTest is Test{
    DeployARC deployer;
    DecentralizedStableCoin arc;
    ARCEngine engine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployARC();
        (arc, engine, config) = deployer.run();
        (ethUsdPriceFeed,, weth,, ) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////////
    ////  PRICE TESTS  ///
    //////////////////////

    function testGetUsdValue() public view{
        uint256 ethAmount = 15e18;
        //15e8 * 2000/ETH = 30000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);

    }
    ///////////////////////////////////
    ////  DEPOSIT COLLATERAL TESTS  ///
    ///////////////////////////////////

    function testConvertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(ARCEngine.ARCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

}