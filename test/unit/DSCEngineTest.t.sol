// SPDX-License-Identifier: MIT



pragma solidity 0.8.19;

import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {Test,console} from "forge-std/Test.sol";
import {DeployDsc} from "../../script/DeployDsc.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import{IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import{MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
contract DSCEngineTest is Test{
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    HelperConfig public config;

    uint256 public constant AMOUNT_COLLETERAL=10 ether;
    uint256 public constant STARTING_TOKEN_BALANCE=10 ether;
    uint256 public constant AMOUNT_TO_MINT= 100 ether;
    uint256 public constant AMOUNT_TO_BURN=100 ether;
    uint256 public constant AMOUNT_TO_LIQUIDATE=30 ether;

    address public ethUsdPriceFeed;
    address public btcUsdPricefeed;
    address public weth;
    address public USER=makeAddr("user");
    address public RAN_ACCOUNT=makeAddr("ran");
    address public LIQUIDATOR=makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    /**********************************
     *          EVENTS                *
     *********************************/
    event ColleteralDeposited(address indexed user,address indexed token,uint256 amount);
    event ColleteralRedeemed(address indexed redeemedFrom,address indexed redeemedTo,address indexed token,uint256  amount);
    event Transfer(address indexed from, address indexed to, uint256 value);
   

    function setUp()public{
      DeployDsc deploy=new DeployDsc();

      (dsc,dscEngine,config)=deploy.run();
      (ethUsdPriceFeed,btcUsdPricefeed ,weth, , )=config.activeNetworkConfig();

      ERC20Mock(weth).mint(USER,STARTING_TOKEN_BALANCE);
     
    }
    /**********************************
     *   CONSTRUCTOR TESTS            *
     *********************************/
     address[]public tokenAddresses;
     address[]public priceFeedAddresses;
     function testRevertIfTokenlengthDoesntMatchPriceFeeds()public{
         tokenAddresses.push(weth);
         priceFeedAddresses.push(ethUsdPriceFeed);
         priceFeedAddresses.push(btcUsdPricefeed);
         vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceFeedAddressLengthInEqual.selector);
         new DSCEngine(tokenAddresses,priceFeedAddresses,address(dsc));
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

     function testGetTokenAmountFromUsd()public{
      uint256 usdAmount=100 ether;
      uint256 expectedWeth=0.05 ether;

      uint256 actualWeth=dscEngine.getTokenAmountFromUsd(address(weth),usdAmount);
      assertEq(actualWeth,expectedWeth);
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

    function testRevertsWithUnapprovedColleteral()public{
     
      ERC20Mock ranToken=new ERC20Mock("RAN","RN",USER, AMOUNT_COLLETERAL);
      vm.startPrank(USER);
      vm.expectRevert(DSCEngine.DecentralizedStableCoin__NotAllowedToken.selector);
      dscEngine.depositColleteral(address(ranToken),AMOUNT_COLLETERAL);
      vm.stopPrank();
    }

    modifier depositedColleteral(){
      vm.startPrank(USER);
      ERC20Mock(weth).approve(address(dscEngine),AMOUNT_COLLETERAL);
      dscEngine.depositColleteral(address(weth),AMOUNT_COLLETERAL);
      vm.stopPrank();
      _;
    } 

      modifier depositedColleteralandMint(){
      vm.startPrank(USER);
      ERC20Mock(weth).approve(address(dscEngine),AMOUNT_COLLETERAL);
      dscEngine.depositColleteralAndMintDsc(address(weth),AMOUNT_COLLETERAL,AMOUNT_TO_MINT);
      
      _;
    } 

    function testCanDepositColleteralAndGetAccountInfo()public depositedColleteral{
      (uint256 totalDscMinted,uint256 colleteralValueInUsd)=dscEngine.getAccountInformation(USER);
      uint256 expectedMintedDcsAmount=0;
      uint256 expectedDepositAmount=dscEngine.getTokenAmountFromUsd(weth,colleteralValueInUsd);
      assertEq(expectedMintedDcsAmount,totalDscMinted);
      assertEq(expectedDepositAmount,AMOUNT_COLLETERAL);
    }

  
    function testCanDepositAndEmitEvent()public  {
   
      vm.startPrank(USER);
      ERC20Mock(weth).approve(address(dscEngine),AMOUNT_COLLETERAL);
      vm.expectEmit(address(dscEngine));

      emit ColleteralDeposited(USER,address(weth),AMOUNT_COLLETERAL);
      dscEngine.depositColleteral(address(weth),AMOUNT_COLLETERAL);
      vm.stopPrank();
    }

    function testDepositColleteralRevertsIfTranferFromFails()public {
      vm.startPrank(USER);
      ERC20Mock(weth).approve(address(dscEngine),AMOUNT_COLLETERAL);
      vm.expectRevert();
      dscEngine.depositColleteral(address(weth),AMOUNT_COLLETERAL+1 ether);
      vm.stopPrank();
    }

    function testCantMintDscTokenIfItBreaksHealthFactor()public depositedColleteral{
      //vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
      uint256 _amountTomint=19_000 ether;
      vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector,526315789473684210));
      vm.startPrank(USER);
      //we deposit 10 ether weth which is value of 
      dscEngine.mintDSC(_amountTomint);
      //This console.log breaks the test --> with Division by 0...
      //
      vm.stopPrank();
    }
     
    function testCandepositColleteralAndMintDscAndEmitsEvents() public {
      uint256 _amountTomint=10_000 ether;
      vm.startPrank(USER);
      ERC20Mock(weth).approve(address(dscEngine),AMOUNT_COLLETERAL);
      vm.expectEmit(address(dscEngine));
      emit ColleteralDeposited(USER,address(weth),AMOUNT_COLLETERAL);
      dscEngine.depositColleteralAndMintDsc(address(weth),AMOUNT_COLLETERAL,_amountTomint);

    }

    function testCanredeemColleteralIfnotBreaksHealthFactor()public depositedColleteral{

      vm.startPrank(USER);
      vm.expectEmit();
      emit ColleteralRedeemed(USER,USER,address(weth),AMOUNT_COLLETERAL); 
      dscEngine.redeemColleteral(address(weth),AMOUNT_COLLETERAL);

      vm.stopPrank();
    }

    function testCanBurnDscToken()public depositedColleteralandMint{
      uint256 _burnAmount=100 ether;
      console.log("Before burning dsc Token balance:",dsc.balanceOf(USER));
      vm.startPrank(USER);
      dsc.approve(address(dscEngine), _burnAmount);
      dscEngine.burnDsc(_burnAmount);
       console.log("After burning dsc Token balance:",dsc.balanceOf(USER));
       console.log("Health-factor after burning:",dscEngine.getHealthFactor(USER));
      vm.stopPrank();
      assertEq(dsc.balanceOf(USER),0);
    }

    function testCanredeemColleteralforDsc()public depositedColleteralandMint{
      vm.startPrank(USER);
      //need to give rights to dscEngine so it can burn the tokens...
      dsc.approve(address(dscEngine), AMOUNT_TO_BURN);
      dscEngine.redeemColleteralforDsc(address(weth),AMOUNT_COLLETERAL,AMOUNT_TO_BURN);
      vm.stopPrank();
      assertEq(ERC20Mock(weth).balanceOf(address(dscEngine)),0);
      assertEq(dsc.balanceOf(USER),0);
    }

    function testCanLiquidateBadUser()public  {
      //when double depositandMınt something goes wrong....
      vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLETERAL);
        dscEngine.depositColleteralAndMintDsc(weth, AMOUNT_COLLETERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = dscEngine.getHealthFactor(USER);
        console.log("User Health Factor:",userHealthFactor);
        ERC20Mock(weth).mint(LIQUIDATOR, collateralToCover);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dscEngine), collateralToCover);
        dscEngine.depositColleteralAndMintDsc(weth, collateralToCover, AMOUNT_TO_MINT);
        dsc.approve(address(dscEngine), AMOUNT_TO_MINT);
        dscEngine.liquidate(weth, USER, AMOUNT_TO_MINT); // We are covering their whole debt
        vm.stopPrank();
       

    }
}