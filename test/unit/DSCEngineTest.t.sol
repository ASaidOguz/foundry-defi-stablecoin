// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {DeployDsc} from "../../script/DeployDsc.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract DSCEngineTest is StdCheats,Test{
 event CollateralRedeemed(address indexed redeemedFrom,address indexed redeemedTo,address indexed token,uint256  amount);
    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;
    address public user = address(1);
    

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    function setUp() external{
      DeployDsc deployer=new DeployDsc();
      (dsc,dsce,helperConfig)=deployer.run();
      (ethUsdPriceFeed,btcUsdPriceFeed,weth,wbtc,deployerKey)= helperConfig.activeNetworkConfig();
    if (block.chainid == 31337) {
            vm.deal(user, STARTING_USER_BALANCE);
        }
        // Should we put our integration tests here?
        // else {
        //     user = vm.addr(deployerKey);
        //     ERC20Mock mockErc = new ERC20Mock("MOCK", "MOCK", user, 100e18);
        //     MockV3Aggregator aggregatorMock = new MockV3Aggregator(
        //         helperConfig.DECIMALS(),
        //         helperConfig.ETH_USD_PRICE()
        //     );
        //     vm.etch(weth, address(mockErc).code);
        //     vm.etch(wbtc, address(mockErc).code);
        //     vm.etch(ethUsdPriceFeed, address(aggregatorMock).code);
        //     vm.etch(btcUsdPriceFeed, address(aggregatorMock).code);
        // }

        ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(user, STARTING_USER_BALANCE);
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////
    address[] public tokenAddresses;
    address[] public feedAddresses;

        function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        feedAddresses.push(ethUsdPriceFeed);
        feedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceFeedAddressLengthInEqual.selector);
        new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
    }

    //////////////////
    // Price Tests //
    //////////////////

    function testGetTokenAmountFromUsd() public {
        // If we want $100 of WETH @ $2000/WETH, that would be 0.05 WETH
        uint256 expectedWeth = 0.05 ether;
        uint256 amountWeth = dsce.getTokenAmountFromUsd(weth, 100 ether);
        assertEq(amountWeth, expectedWeth);
    }

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 ETH * $2000/ETH = $30,000e18
        uint256 expectedUsd = 30000e18;
        uint256 usdValue = dsce.getUsdValue(weth, ethAmount);
        assertEq(usdValue, expectedUsd);
    }

     function testRevertsIfTransferFromFails() public{
      address owner =msg.sender;

        vm.prank(owner);
        MockFailedTransferFrom failedDsc= new MockFailedTransferFrom();
        tokenAddresses = [address(failedDsc)];
        feedAddresses = [ethUsdPriceFeed];
        DSCEngine dscEngine= new DSCEngine(tokenAddresses,feedAddresses,address(failedDsc));

        failedDsc.mint(user, amountCollateral);

        vm.prank(owner);
        failedDsc.transferOwnership(address(dscEngine));

                // Arrange - User
        vm.startPrank(user);
        ERC20Mock(address(failedDsc)).approve(address(dscEngine), amountCollateral);

        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dscEngine.depositCollateral(address(failedDsc), amountCollateral);
        vm.stopPrank();
     }

      function testRevertsIfCollateralZero() public{
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThenZero.selector);
        dsce.depositCollateral(weth,0);
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThenZero.selector);
        dsce.depositCollateralAndMintDsc(weth,0,0);  
      }

        function testRevertsWithUnapprovedCollateral() public {
          ERC20Mock mockWeth= new ERC20Mock("RAN", "RAN", user, 100e18);
          vm.prank(user);
          vm.expectRevert(abi.encodeWithSelector(DSCEngine.DecentralizedStableCoin__NotAllowedToken.selector,address(mockWeth)));
          dsce.depositCollateral(address(mockWeth),100 ether);
        }

        modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        _;
    }

     function testCanDepositCollateralWithoutMinting() public depositedCollateral{
        uint256 dscBalanceofUser=dsc.balanceOf(user);
        uint256 depositedColleteralbyUser=dsce.getCollateralBalanceOfUser(user,weth);
        assertEq(amountCollateral,depositedColleteralbyUser);
        assertEq(dscBalanceofUser,0);
     }

     function testCanDepositedCollateralAndGetAccountInfo()  public depositedCollateral{
      (uint256 totalDscMinted,uint256 colleteralValueinUsd)=dsce.getAccountInformation(user);
      uint256 expectedAmount=dsce.getTokenAmountFromUsd(weth,colleteralValueinUsd);
      assertEq(totalDscMinted,0);
      assertEq(expectedAmount,amountCollateral);
     }

     ///////////////////////////////////////
    // depositCollateralAndMintDsc Tests //
    ///////////////////////////////////////

     function testRevertsIfMintedDscBreaksHealthFactor() public{
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint = (amountCollateral * (uint256(price) * dsce.getAdditionalFeedPrecision())) / dsce.getPrecision();
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);

        uint256 expectedHealthFactor =
            dsce.calculateHealthFactor(amountToMint, dsce.getUsdValue(weth, amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
     }

         modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, amountToMint);
    }

    ///////////////////////////////////
    // mintDsc Tests //
    ///////////////////////////////////
    // This test needs it's own custom setup
    function testRevertsIfMintFails() public{
      address owner=msg.sender;

      vm.startPrank(owner);
      MockFailedMintDSC failedMintDsc=new MockFailedMintDSC();
        tokenAddresses = [weth];
        feedAddresses = [ethUsdPriceFeed];
      dsce=new DSCEngine(tokenAddresses,feedAddresses,address(failedMintDsc));
      failedMintDsc.transferOwnership(address(dsce));
      vm.stopPrank();
      vm.startPrank(user);
      ERC20Mock(weth).approve(address(dsce), amountCollateral);
      vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
      dsce.depositCollateralAndMintDsc(weth,amountCollateral,amountToMint);
      vm.stopPrank();
    }

    function testRevertsIfMintAmountIsZero() public {
      vm.startPrank(user);
      ERC20Mock(weth).approve(address(dsce), amountCollateral);
      dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
      vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThenZero.selector);
      dsce.mintDSC(0);
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public{
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint = (amountCollateral * (uint256(price) * dsce.getAdditionalFeedPrecision())) / dsce.getPrecision();

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(weth, amountCollateral);

        uint256 expectedHealthFactor =
            dsce.calculateHealthFactor(amountToMint, dsce.getUsdValue(weth, amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dsce.mintDSC(amountToMint);
        vm.stopPrank();
    }

     function testCanMintDsc() public depositedCollateral{
      vm.prank(user);
      dsce.mintDSC(amountToMint);

        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, amountToMint);
     }

    ///////////////////////////////////
    // burnDsc Tests //
    ///////////////////////////////////
    modifier depositAndMintDsc(){
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(weth, amountCollateral);
        dsce.mintDSC(amountToMint);
        vm.stopPrank();
      
      _;
    }



    function testRevertsIfBurnAmountIsZero() public depositAndMintDsc{
         vm.prank(user);
         vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThenZero.selector);
         dsce.burnDsc(0);
    }

    function testCantBurnMoreThanUserHas()public{
      vm.prank(user);
      vm.expectRevert();
      dsce.burnDsc(1);
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc{
      vm.startPrank(user);
      dsc.approve(address(dsce),amountToMint);
      dsce.burnDsc(amountToMint);
      vm.stopPrank();
      uint256 userBalance=dsc.balanceOf(user);
      assertEq(userBalance,0);
    }

    ///////////////////////////////////
    // redeemCollateral Tests //
    //////////////////////////////////

    // this test needs it's own setup
    function testRevertsIfTransferFails() public{
         // Arrange - Setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransfer mockDsc = new MockFailedTransfer();
        tokenAddresses = [address(mockDsc)];
        feedAddresses = [ethUsdPriceFeed];
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(
            tokenAddresses,
            feedAddresses,
            address(mockDsc)
        );
        mockDsc.mint(user, amountCollateral);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(address(mockDsc)).approve(address(mockDsce), amountCollateral);
        // Act / Assert
        mockDsce.depositCollateral(address(mockDsc), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.redeemCollateral(address(mockDsc), amountCollateral);
        vm.stopPrank();
    }

        function testRevertsIfRedeemAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThenZero.selector);
        dsce.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositedCollateral{
      vm.startPrank(user);
      uint256 colleteralToredeem=dsce.getCollateralBalanceOfUser(user,weth);
      dsce.redeemCollateral(weth,colleteralToredeem);
        uint256 userBalance = ERC20Mock(weth).balanceOf(user);
        vm.stopPrank();
        assertEq(userBalance, amountCollateral);
    }

    function testEmitCollateralRedeemedWithCorrectArgs() public  {
       
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(weth, amountCollateral);
  vm.expectEmit(true, true, true, true, address(dsce));
  emit CollateralRedeemed(user, user, weth, amountCollateral); 
        dsce.redeemCollateral(weth, amountCollateral);   
        vm.stopPrank();
    }

    ///////////////////////////////////
    // redeemCollateralForDsc Tests //
    //////////////////////////////////

    function testMustRedeemMoreThanZero() public depositedCollateralAndMintedDsc{
        vm.startPrank(user);
        dsc.approve(address(dsce), amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThenZero.selector);
        dsce.redeemCollateralforDsc(weth, 0, amountToMint);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public depositedCollateralAndMintedDsc{
        vm.startPrank(user);
        dsc.approve(address(dsce), amountToMint);
        dsce.redeemCollateralforDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        uint256 userBalance=ERC20Mock(weth).balanceOf(user);
        uint256 userDscBalance=dsc.balanceOf(user);
        assertEq(userBalance,amountCollateral);
        assertEq(userDscBalance,0);
    }

    ////////////////////////
    // healthFactor Tests //
    ////////////////////////

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc{
      // deposit and mint dsc -> manuely calculate the health factor?
      // use getter to get health factor from contract and assert... amountToMint-amountCollateral
     
        uint256 expectedHealthFactor = 100 ether;
        uint256 healthFactor = dsce.getHealthFactor(user);
        // $100 minted with $20,000 collateral at 50% liquidation threshold
        // means that we must have $200 collatareral at all times.
        // 20,000 * 0.5 = 10,000
        // 10,000 / 100 = 100 health factor
        assertEq(healthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc{
      //lets change MockAggregators answer so healthfactor go below one...
      int256 breakerAnswer=18e8; // aggregator decimal 8-> s0 this means $18
      MockV3Aggregator(ethUsdPriceFeed).updateAnswer(breakerAnswer);
      vm.startPrank(user);
      uint256 healthFactor = dsce.getHealthFactor(user);
      vm.stopPrank();
      assert(healthFactor<MIN_HEALTH_FACTOR);
    }

    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    // This test needs it's own setup
    function testMustImproveHealthFactorOnLiquidation() public{
 // Arrange - Setup
        MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPriceFeed);
        tokenAddresses = [weth];
        feedAddresses = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(
            tokenAddresses,
            feedAddresses,
            address(mockDsc)
        );
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockDsce), amountCollateral);
        mockDsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        // Arrange - Liquidator
        collateralToCover = 1 ether;
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(mockDsce), collateralToCover);
        uint256 debtToCover = 10 ether;
        mockDsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        mockDsc.approve(address(mockDsce), debtToCover);
        // Act
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        // Act/Assert
        vm.expectRevert(DSCEngine.DSCEngine__HealthNotImproved.selector);
        mockDsce.liquidate(weth, user, debtToCover);
        vm.stopPrank();
    
    }

    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc{
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dsce), collateralToCover);
        dsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        dsc.approve(address(dsce), amountToMint);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, user, amountToMint);
        vm.stopPrank();
    }

     modifier liquidated(){
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = dsce.getHealthFactor(user);

        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dsce), collateralToCover);
        dsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        dsc.approve(address(dsce), amountToMint);
        dsce.liquidate(weth, user, amountToMint); // We are covering their whole debt
        vm.stopPrank();

      _;
     }

      function testLiquidationPayoutIsCorrect() public liquidated{
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
        uint256 expectedWeth = dsce.getTokenAmountFromUsd(weth, amountToMint)
            + (dsce.getTokenAmountFromUsd(weth, amountToMint) / dsce.getLiquidationBonus());
        uint256 hardCodedExpected = 6111111111111111110;
        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
      }

      function testUserStillHasSomeEthAfterLiquidation() public liquidated{
        // Get how much WETH the user lost
        uint256 amountLiquidated = dsce.getTokenAmountFromUsd(weth, amountToMint)
            + (dsce.getTokenAmountFromUsd(weth, amountToMint) / dsce.getLiquidationBonus());

        uint256 usdAmountLiquidated = dsce.getUsdValue(weth, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd = dsce.getUsdValue(weth, amountCollateral) - (usdAmountLiquidated);

        (, uint256 userCollateralValueInUsd) = dsce.getAccountInformation(user);
        uint256 hardCodedExpectedValue = 70000000000000000020;
        assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
        assertEq(userCollateralValueInUsd, hardCodedExpectedValue);
      }

      function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDscMinted,) = dsce.getAccountInformation(liquidator);
        assertEq(liquidatorDscMinted, amountToMint);
    }

        function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted,) = dsce.getAccountInformation(user);
        assertEq(userDscMinted, 0);
    }

     ///////////////////////////////////
    // View & Pure Function Tests //
    //////////////////////////////////
    function testGetCollateralTokenPriceFeed() public {
        address priceFeed = dsce.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, ethUsdPriceFeed);
    }

    function testGetCollateralTokens() public {
        address[] memory collateralTokens = dsce.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function testGetMinHealthFactor() public {
        uint256 minHealthFactor = dsce.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testGetLiquidationThreshold() public {
        uint256 liquidationThreshold = dsce.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testGetAccountCollateralValueFromInformation() public depositedCollateral {
        (, uint256 collateralValue) = dsce.getAccountInformation(user);
        uint256 expectedCollateralValue = dsce.getUsdValue(weth, amountCollateral);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        uint256 collateralBalance = dsce.getCollateralBalanceOfUser(user, weth);
        assertEq(collateralBalance, amountCollateral);
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        uint256 collateralValue = dsce.getAccountCollateralValue(user);
        uint256 expectedCollateralValue = dsce.getUsdValue(weth, amountCollateral);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetDsc() public {
        address dscAddress = dsce.getDsc();
        assertEq(dscAddress, address(dsc));
    }
}