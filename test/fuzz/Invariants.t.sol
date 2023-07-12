
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
//You can inspect any Contracts methods with "forge inspect <Contract-name> methods"
//Have our invariants aka properties

//what our invariants?

// 1. total supply of DSC should be lower than total value of colleteral
// 2. Getter functions should never revert <- everGreen invariant
import {Test,console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDsc} from "../../script/DeployDsc.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import{IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import{Handler} from "./Handler.t.sol";
contract InvariantTest is StdInvariant,Test{
    DeployDsc public deployer;
    DSCEngine public dscEngine;
    HelperConfig public config;
    DecentralizedStableCoin public dsc;
    Handler public handler;
    address public weth;
    address public wbtc;

function setUp() external{
  deployer=new DeployDsc();
  (dsc,dscEngine,config)=deployer.run();
  ( , ,weth,wbtc, )=config.activeNetworkConfig();
  //targetContract(address(dscEngine));
  handler=new Handler(dsc,dscEngine);
  targetContract(address(handler));
}

function invariant_protocolMusthaveMoreValueThenSupply() public view{
       //get the value of all colleteral in the protocol
       //compare it with all the debt
       uint256 totalSupplyOfDsc=dsc.totalSupply();
       uint256 totalWethDeposited=IERC20(weth).balanceOf(address(dscEngine));
       uint256 totalWbtcDeposited=IERC20(wbtc).balanceOf(address(dscEngine));

       uint256 wethValue=dscEngine.getUsdValue(weth,totalWethDeposited);
       uint256 wbtcValue=dscEngine.getUsdValue(wbtc,totalWbtcDeposited);
       console.log("weth-value:",wethValue);
       console.log("wbtc-Value:",wbtcValue);
       console.log("Total-supply of Dsc:",totalSupplyOfDsc);
       console.log("Times mint is called",handler.timesMintisCalled());
       assert(wethValue+wbtcValue>=totalSupplyOfDsc);

}

function invariant_GetterFunctionsNeverRevert()public view{
        dscEngine.getAdditionalFeedPrecision();
        dscEngine.getCollateralTokens();
        dscEngine.getLiquidationBonus();
        dscEngine.getLiquidationBonus();
        dscEngine.getLiquidationThreshold();
        dscEngine.getMinHealthFactor();
        dscEngine.getPrecision();
        dscEngine.getDsc();
}
}