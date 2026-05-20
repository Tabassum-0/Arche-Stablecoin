// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {ARCEngine} from "../src/ARCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployARC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin, ARCEngine) {
        HelperConfig config = new HelperConfig();

        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast();
        DecentralizedStableCoin arc = new DecentralizedStableCoin(msg.sender);
        ARCEngine engine = new ARCEngine(tokenAddresses, priceFeedAddresses, address(arc));

        arc.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (arc, engine);
    }
}
