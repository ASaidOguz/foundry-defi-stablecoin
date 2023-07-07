// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity 0.8.19;

/*
 * @title DSCEngine
 * @author Ahmet Said Oguz
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 * @notice: we follow CEI checks-effects-interactions
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
contract DSCEngine is ReentrancyGuard{
    //! ///////////////////////////////// 
    //! ////////// Errors ////////////// 
    //! ///////////////////////////////
    
     error DSCEngine__MustBeMoreThenZero();
     error DSCEngine__TokenAddressAndPriceFeedAddressLengthInEqual();
     error DecentralizedStableCoin__NotAllowedToken();
     error DSCEngine__TransferFailed();
     error DSCEngine__BreaksHealthFactor(uint256 healthfactor);
     error DSCEngine__MintFailed();
    //! ///////////////////////////////// 
    //! ////////// State-Variables /////
    //! ///////////////////////////////
    mapping(address token=>address priceFeed) private s_priceFeeds;
    mapping(address user=>mapping(address token=> uint256 amount)) private s_colleteralDeposited;
    mapping(address=>uint256 amountMintedDsc) private s_DSCMinted;
    address[] private s_colleteralTokens;

    uint256 private constant ADDITIONAL_FEED_PRECISION=1e10;
    uint256 private constant PRECISION=1e18;
    uint256 private constant LQUIDATION_THRESHOLD=50;
    uint256 private constant LQUIDATION_PRECISION=100;
    uint256 private constant MIN_HEALTH_FACTOR=1;

    DecentralizedStableCoin private immutable i_decentralizedStableCoin;
    //! ///////////////////////////////// 
    //! ////////// Events ////////////// 
    //! ///////////////////////////////

    event ColleteralDeposited(address indexed user,address indexed token,uint256 amount);
    //! ///////////////////////////////// 
    //! ////////// Modifiers /////////// 
    //! ///////////////////////////////

    modifier moreThanZero(uint256 _amount){
        if(_amount==0){
            revert DSCEngine__MustBeMoreThenZero();
        }
       _;
    }

    modifier isAllowedToken(address _tokenAddress){
       if(s_priceFeeds[_tokenAddress]==address(0)){
        revert DecentralizedStableCoin__NotAllowedToken();
       }
       _;
    }
    //! ///////////////////////////////// 
    //! ////////// Functions /////////// 
    //! ///////////////////////////////
    constructor(
        address[] memory _tokenAddresses,
        address[] memory _priceFeeds,
        address _dcsAddress){
            if(_tokenAddresses.length!=_priceFeeds.length){
                revert DSCEngine__TokenAddressAndPriceFeedAddressLengthInEqual();
            }
           for(uint256 i=0;i<_tokenAddresses.length;i++){
            s_priceFeeds[_tokenAddresses[i]]=_priceFeeds[i];
            s_colleteralTokens.push(_tokenAddresses[i]);
           }

         i_decentralizedStableCoin= DecentralizedStableCoin(_dcsAddress);
    }
    // External Functions
    function depositColleteralAndMintDsc() external{}

    function redeemColleteralforDsc() external{}

    function depositColleteral(
        address _tokenColleteralAddress,
        uint256 _amountColleteral)external 
        moreThanZero(_amountColleteral) 
        isAllowedToken(_tokenColleteralAddress)
        nonReentrant
        {
            s_colleteralDeposited[msg.sender][_tokenColleteralAddress]+=_amountColleteral;
            emit ColleteralDeposited(msg.sender,_tokenColleteralAddress,_amountColleteral);

        bool success=IERC20(_tokenColleteralAddress).transferFrom(msg.sender,address(this),_amountColleteral);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
    }


    /**
     * 
     * @notice They must have more colleteral then the minimum threshold;
     */
    function mintDSC(uint256 _amountDsctoMint) external 
        moreThanZero(_amountDsctoMint) 
        nonReentrant
        {
        s_DSCMinted[msg.sender]+=_amountDsctoMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted=i_decentralizedStableCoin.mint(msg.sender,_amountDsctoMint);
        if(!minted){
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc() external{}

    function liquidate() external{}

    function getHealthFactor() external view{}

    //! ////////////////////////////////////////////////// 
    //! ////////// Private &Internal view Functions /////
    //! /////////////////////////////////////////////////
    function _getAccountInformation(address user) private 
                                                  view
                                                  returns(uint256 totalDSCMinted,uint256 colleteralValueInUsd){
        totalDSCMinted=s_DSCMinted[user];
        colleteralValueInUsd=getAccountColleteralValue(user);
    }
    function _healthFactor(address user)private view returns(uint256){
        // 1. total minted DSC
        // 2. total colleteral value

        (uint256 totalDscminted,uint256 colleteralValueInUsd)=_getAccountInformation(user);
        /* return (colleteralValueInUsd/totalDscminted); */
        uint256 colleteralAdjustedThreshold=(colleteralValueInUsd*LQUIDATION_THRESHOLD)/LQUIDATION_PRECISION;
        // $1000 dolar değerinde ether ve 100 DSC token
        // $1000 * 50=50000/100=500/100=> 1 den büyük olacaktır.
        
        //$150 ETH /100 DSC=1.5
        //150 *50=7500/100=75/100<1
        return ((colleteralAdjustedThreshold*PRECISION)/totalDscminted);
    }
             // 1. Check health factor(do they enough colleteral)
             // 2. Revert if they dont have good health factor
    function _revertIfHealthFactorIsBroken(address user) internal  view{

        uint256 userHealthFactor=_healthFactor(user);
        if(userHealthFactor<MIN_HEALTH_FACTOR){
          revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }

    }
    //! /////////////////////////////////////////// 
    //! ////////// Public&external view Functions//
    //! //////////////////////////////////////////

    function getAccountColleteralValue(address user) public view returns(uint256 totalColleteralValueInUsd){
        for(uint256 i=0;i<s_colleteralTokens.length;i++){
           address token=s_colleteralTokens[i];
           uint256 amount=s_colleteralDeposited[user][token];
           totalColleteralValueInUsd+=getUsdValue(token,amount);
        }
        return totalColleteralValueInUsd;
    }

    function getUsdValue(address _token,uint256 _amount) public view returns(uint256){
    AggregatorV3Interface priceFeed= AggregatorV3Interface(s_priceFeeds[_token]);
    (,int256 price,,,)=priceFeed.latestRoundData();
    // 1 Eth= $1000;
    // The return value of CL will be 1000*1e8;
     return  (((uint256(price)*ADDITIONAL_FEED_PRECISION)*_amount)/PRECISION);               
    }

}