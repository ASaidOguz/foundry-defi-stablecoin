// SPDX-License-Identifier: MIT



pragma solidity 0.8.19;

import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";
import {DeployDsc} from "../../script/DeployDsc.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test{
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    HelperConfig public config;

    uint256 public constant AMOUNT_COLLETERAL=10 ether;
    uint256 public constant STARTING_TOKEN_BALANCE=10 ether;

    address public ethUsdPriceFeed;
    address public weth;
    address public USER=makeAddr("user");
    
    function setUp()public{
      DeployDsc deploy=new DeployDsc();

      (dsc,dscEngine,config)=deploy.run();
      (ethUsdPriceFeed, ,weth, , )=config.activeNetworkConfig();

      ERC20Mock(weth).mint(USER,STARTING_TOKEN_BALANCE);
    }
    /**********************************
     *   PRICE TESTS                  *
     *********************************/

     function testGetUsdValue() public{
        //this test fails cause we r hardcoding the value...
    uint256 ethAmount=15e18;
     //15e18*2000/ETH=30,000 e18
     uint256 expectedUsd=30_000e18;
     uint256 actualUsd=dscEngine.getUsdValue(weth,ethAmount);
     assertEq(actualUsd,expectedUsd);
     }

    /**************************************
     *    DEPOSIT-COLLETERAL TESTS        *
    ***************************************/

    function testRevertsIfColleteralisZero()public{
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(dscEngine),AMOUNT_COLLETERAL);

    vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThenZero.selector);
    dscEngine.depositColleteral(weth,0);

    vm.stopPrank();
    }
}