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


contract DecentralizedStableCoinTest is StdCheats,Test{
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
    address public owner=makeAddr("owner");
    address public deployerAddress=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

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
    //! ///////////////////////
    //!      MODIFIERS   //////
    //! //////////////////////
    modifier transferOwnerShip(){
        //initial deploy script transfer the ownership to dscEngine
        //we'r transfering the ownership to EOA so we can make the test more realistic and 
        //isolated... 
        vm.startPrank(address(dsce));
        dsc.transferOwnership(owner);
        vm.stopPrank();
        
        _;
    }

    modifier transferOwnerShipAndMintForOwner(){
        vm.startPrank(address(dsce));
        dsc.transferOwnership(owner);
        vm.stopPrank();
        vm.startPrank(owner);
        dsc.mint(owner,amountToMint);
        vm.stopPrank();
         _;
    }

    function testCantMintDSCIfnotOwner()public{
        vm.startPrank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dsc.mint(user,amountToMint);
        vm.stopPrank();
    }

    function testCanMintIfOwner() public transferOwnerShip{
        vm.startPrank(owner);
        dsc.mint(user,amountToMint);
        vm.stopPrank();
        assertEq(dsc.balanceOf(user),amountToMint);
    }

    function testCantMintZeroAddress()public transferOwnerShip{
        vm.startPrank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__CantMintZeroAddress.selector);
        dsc.mint(address(0),amountToMint);
        vm.stopPrank();    
    }

    function testCantMintZeroValue()public transferOwnerShip{
        vm.startPrank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThenZero.selector);
        dsc.mint(user,0);
        vm.stopPrank();   
    }

    function testCantBurnIfAmountisZero()public transferOwnerShipAndMintForOwner{  
        vm.startPrank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThenZero.selector);
        dsc.burn(0);
        vm.stopPrank();    
    }

    function testCantburnIfBalanceZero()public transferOwnerShipAndMintForOwner{
        vm.startPrank(owner);
        dsc.transfer(user,amountToMint);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(amountToMint);
        vm.stopPrank();  
    }
}