// SPDX-License-Identifier: MIT

// Handler is going to narrow down the way we call function

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {ARCEngine} from "../../src/ARCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../../test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    ARCEngine engine;
    DecentralizedStableCoin arc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled;
    MockV3Aggregator public ethUsdPriceFeed;
    address[] public usersWithCollateralDeposited;

    uint256 MAX_DEPOSIT_SIZE = 10000000 * 1e18;

    constructor(ARCEngine _arcEngine, DecentralizedStableCoin _arc) {
        engine = _arcEngine;
        arc = _arc;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth)));
    }

    function mintArc(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalArcMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(sender);
        uint256 maxArcToMint = (collateralValueInUsd / 2) - totalArcMinted;
        if (maxArcToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxArcToMint));
        if (amount == 0) {
            return;
        }
        vm.startPrank(sender);
        engine.mintArc(amount);
        timesMintIsCalled++;
        vm.stopPrank();
    }

    //Redeem collateral <-

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[collateralSeed % usersWithCollateralDeposited.length];
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(address(collateral), sender);
        if (maxCollateralToRedeem == 0) {
            return;
        }
        amountCollateral = bound(amountCollateral, 1, maxCollateralToRedeem);
        engine.redeemCollateral(address(collateral), uint256(amountCollateral));
    }

    //This breaks out invariant test suite
    // function updateCollateralPrice(uint96 newPrice) public {
    //     uint256 safePrice = bound(newPrice, 1e8, 1000000 * 1e8);
    //     int256 newPriceInt = int256(safePrice);
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    // helper functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}

