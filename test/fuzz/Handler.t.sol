// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
//handler will narrow down the way we call functions 

import {Test,console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDsc} from "../../script/DeployDsc.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import{IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import{MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";
contract Handler is Test{

    DecentralizedStableCoin public dsc;
    DSCEngine public dscEngine;

    ERC20Mock public weth;
    ERC20Mock public wbtc;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 MAX_DEPOSIT_SIZE=type(uint96).max;// the max value of uint96..
    address[] public usersWithColleteralDeposited;

    uint256 public timesMintisCalled;
   constructor(DecentralizedStableCoin _dsc,DSCEngine _dscEngine){
    dscEngine=_dscEngine;
    dsc=_dsc;

    address[] memory colleteralTokens=dscEngine.getCollateralTokens();
    weth=ERC20Mock(colleteralTokens[0]);
    wbtc=ERC20Mock(colleteralTokens[1]);

    ethUsdPriceFeed=MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth))) ;
   }
   //redeemColleteral <-
   function depositColleteral(uint256 _colleteralSeed,uint256 _amountColleteral)public{
    //dscEngine.depositColleteral(_colleteralSeedAddress,_amountColleteral);
    ERC20Mock _ranColleteral=_getColleteralFromSeed(_colleteralSeed);
    _amountColleteral=bound(_amountColleteral,1,MAX_DEPOSIT_SIZE);

    vm.startPrank(msg.sender);
    _ranColleteral.mint(msg.sender,_amountColleteral);
    _ranColleteral.approve(address(dscEngine),_amountColleteral);
    dscEngine.depositCollateral(address(_ranColleteral),_amountColleteral);   
    vm.stopPrank();
    usersWithColleteralDeposited.push(msg.sender);
   }

   function redeemColleteral(uint256 _colleteralSeed,uint256 _amountColleteral) public{
    ERC20Mock _ranColleteral=_getColleteralFromSeed(_colleteralSeed);
    uint256 maxColleteralToRedeem=dscEngine.getCollateralBalanceOfUser(address(_ranColleteral),msg.sender);
     _amountColleteral=bound(_amountColleteral,0,maxColleteralToRedeem);
     if(_amountColleteral==0){
        return;
     }
     dscEngine.redeemCollateral(address(_ranColleteral),_amountColleteral);

   }

function mintDsc(uint256 _amountToMint,uint256 addressSeed)public{
  if(usersWithColleteralDeposited.length==0){
    return;
  }
  address sender=usersWithColleteralDeposited[addressSeed % usersWithColleteralDeposited.length]; 
  (uint256 totalDscminted,uint256 colleteralValueInUsd)=dscEngine.getAccountInformation(sender);
   
  int maxDscTomint=(int256(colleteralValueInUsd)/2)- int256(totalDscminted);
  if(maxDscTomint<0){
    return;
  }
  
  _amountToMint=bound(_amountToMint,0,uint256(maxDscTomint));
  if(_amountToMint==0){
    return;
  }
 
  vm.startPrank(sender);
  dscEngine.mintDSC(_amountToMint);
  vm.stopPrank();
  timesMintisCalled++;
  
}
// this function breaks our invariant cause it manupilates the price and changes colleteral-dsc balance
/* 
    function updateColleteralPrice(uint96 _newPrice)public{
    int256 newPriceInt=int256(uint256(_newPrice));
    ethUsdPriceFeed.updateAnswer(newPriceInt);
} 
*/
   //Helper functions
   function _getColleteralFromSeed(uint256 _colleteralSeed)internal view returns(ERC20Mock){
     if(_colleteralSeed%2==0){
        return weth;
     }
     return wbtc;
   }
}