// SPDX-License-Identifier: MIT

// Have our invairiant aka properties

/**
 * Our invariants:
 * 1. The total supply of ARC should be less than the total value of collateral
 * 2. Getter view functions should never revert <- evergreen invariant
 */

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployARC} from "../../script/DeployARC.s.sol";
import {ARCEngine} from "../../src/ARCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantTest is StdInvariant, Test {
    DeployARC deployer;
    ARCEngine engine;
    DecentralizedStableCoin arc;
    HelperConfig config;
    Handler handler;
    address weth;
    address wbtc;

    function setUp() public {
        deployer = new DeployARC();
        (arc, engine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(engine, arc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        //get the value of all the collateral in the protocol
        //compare it to all the debt(Arc)
        uint256 totalSupply = arc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("weth value: ", wethValue);
        console.log("wbtc value: ", wbtcValue);
        console.log("Total supply: ", totalSupply);
        console.log("Times mint called: ", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    /**
     * function invariant_gettersShouldNotRevert() public view{
     *     engine.getAccountCollateralValue();
     *     engine.getPrecision();
     *     engine.getSepoliaEthConfig();
     *     engine.getUsdValue();
     *     engine.getLiquidationBonus();
     *     engine.getLiquidationPrecision();
     *     engine.getLiquidationThreshold();
     *     engine.getCollateralBalanceOfUser();
     *     engine.getCollateralTokenPriceFeed();
     *     engine.getAccountCollateralValue();
     *     engine.getCollateralTokens();
     *     engine.getAccountInformation();
     *     engine.getTokenAmountFromUsd();
     *     engine.getAdditionalFeedPrecision();
     *     engine.getArc();
     *     engine.getHealthFactor();
     *     engine.getMinHealthFactor();
     * }
     */
}

