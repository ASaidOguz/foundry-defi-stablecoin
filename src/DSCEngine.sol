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
import{OracleLib} from "./libraries/OracleLib.sol";
contract DSCEngine is ReentrancyGuard{
    //! ///////////////////////////////// 
    //! ////////// Errors ////////////// 
    //! ///////////////////////////////
    
     error DSCEngine__MustBeMoreThenZero();
     error DSCEngine__TokenAddressAndPriceFeedAddressLengthInEqual();
     error DecentralizedStableCoin__NotAllowedToken(address tokenAddress);
     error DSCEngine__TransferFailed();
     error DSCEngine__BreaksHealthFactor(uint256 healthfactor);
     error DSCEngine__MintFailed();
     error DSCEngine__HealthFactorOk();
     error DSCEngine__HealthNotImproved();
    //! ///////////////////////////////// 
    //! ///////      TYPES         /////
    //! ///////////////////////////////
    using OracleLib for AggregatorV3Interface;
    //! ///////////////////////////////// 
    //! ////////// State-Variables /////
    //! ///////////////////////////////
    mapping(address token=>address priceFeed) private s_priceFeeds;
    mapping(address user=>mapping(address token=> uint256 amount)) private s_colleteralDeposited;
    mapping(address=>uint256 amountMintedDsc) private s_DSCMinted;
    address[] private s_colleteralTokens;

    uint256 private constant ADDITIONAL_FEED_PRECISION=1e10;
    uint256 private constant PRECISION=1e18;
    uint256 private constant LIQUIDATION_THRESHOLD=50;
    uint256 private constant LIQUIDATION_PRECISION=100;
    uint256 private constant MIN_HEALTH_FACTOR=1e18;
    uint256 private constant LIQUIDATION_BONUS=10; // dat means %10 bonus

    DecentralizedStableCoin private immutable i_decentralizedStableCoin;
    //! ///////////////////////////////// 
    //! ////////// Events ////////////// 
    //! ///////////////////////////////

    event CollateralDeposited(address indexed user,address indexed token,uint256 amount);
    //1 difference in indexed identifier can fail the emit test...
    event CollateralRedeemed(address indexed redeemedFrom,address indexed redeemedTo,address indexed token,uint256  amount);
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
        revert DecentralizedStableCoin__NotAllowedToken(_tokenAddress);
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
    //! ////////////////////////////////////////////////// 
    //! //////////       External Functions         /////
    //! /////////////////////////////////////////////////

        /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountDscToMint: The amount of DSC you want to mint
     * @notice This function will deposit your collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(address _tokenColleteral,
            uint256 _amountColleteral,
            uint256 _amountDscMint) public{
            depositCollateral(_tokenColleteral,_amountColleteral);
            mintDSC(_amountDscMint);
            }
  
        /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're redeeming
     * @param amountCollateral: The amount of collateral you're redeeming
     * @notice This function will redeem your collateral.
     * @notice If you have DSC minted, you will not be able to redeem until you burn your DSC
     */
    function redeemCollateral(
             address _tokenColleteralAddress,
             uint256 _amountColleteral) public 
             moreThanZero(_amountColleteral)
             nonReentrant{
        _redeemCollateral(_tokenColleteralAddress,_amountColleteral,msg.sender,msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }
      /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountDscToBurn: The amount of DSC you want to burn
     * @notice This function will withdraw your collateral and burn DSC in one transaction
     */
     function redeemCollateralforDsc(address _tokenColleteralAddress,
        uint256 _amountColleteral,
        uint256 _amountDcsToburn)public{
         burnDsc(_amountDcsToburn);
         redeemCollateral(_tokenColleteralAddress,_amountColleteral);
     }
    function depositCollateral(
        address _tokenColleteralAddress,
        uint256 _amountColleteral)public 
        moreThanZero(_amountColleteral) 
        isAllowedToken(_tokenColleteralAddress)
        nonReentrant
        {
            s_colleteralDeposited[msg.sender][_tokenColleteralAddress]+=_amountColleteral;
            emit CollateralDeposited(msg.sender,_tokenColleteralAddress,_amountColleteral);

            bool success=IERC20(_tokenColleteralAddress).transferFrom(msg.sender,address(this),_amountColleteral);
            //redundant check----->           
            if(!success){
                revert DSCEngine__TransferFailed();
            }
    }


    /**
     * 
     * @notice They must have more colleteral then the minimum threshold;
     */
    function mintDSC(uint256 _amountDsctoMint) public 
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

    function burnDsc(uint256 _amountToBurn) public moreThanZero(_amountToBurn){
        _burnDsc(_amountToBurn,msg.sender,msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }
    /*
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     *
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(address _colleteralAddress,
                        address _user,
                        uint256 _debtToCover) external 
                        moreThanZero(_debtToCover)
                        {
        uint256 startingUserHealthFactor=_healthFactor(_user);
        if(startingUserHealthFactor>=MIN_HEALTH_FACTOR){
            revert DSCEngine__HealthFactorOk();
        }
        //We want to burn their DSC"debt"...
        //and take their colleteral... 
        //bad user:$140 ETH- 100 DSC 
        //debt to Cover= $100
        // $100 DSC == ?? ETH

        uint256 tokenAmountFromDebtCovered=getTokenAmountFromUsd(_colleteralAddress,_debtToCover);
        //and we give them %10 bonus for liquidation

        uint256 bonusColleteral=(tokenAmountFromDebtCovered*LIQUIDATION_BONUS)/LIQUIDATION_PRECISION;
        //0.05*0.1=0.055

        uint256 totalColleteralToRedeem=tokenAmountFromDebtCovered+bonusColleteral;

        _redeemCollateral(_colleteralAddress,totalColleteralToRedeem,_user,msg.sender);
        _burnDsc(_debtToCover,_user,msg.sender);
        uint256 endingHealthFactor=_healthFactor(_user);
        if(endingHealthFactor<=startingUserHealthFactor){
         revert DSCEngine__HealthNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }



    //! ////////////////////////////////////////////////// 
    //! ////////// Private &Internal view Functions /////
    //! /////////////////////////////////////////////////

    function _burnDsc(uint256 _amountDscToBurn,address _onBehalfOf,address _dscFrom) private{
        s_DSCMinted[_onBehalfOf]-=_amountDscToBurn;
        bool success=i_decentralizedStableCoin.transferFrom(_dscFrom,address(this),_amountDscToBurn);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
        i_decentralizedStableCoin.burn(_amountDscToBurn);
    }

    function _redeemCollateral(address _tokenColleteralAddress,uint256 _amountColleteral,address _from,address _to)private{
        //if underflow it will revert ...   
        s_colleteralDeposited[_from][_tokenColleteralAddress]-=_amountColleteral;
        //we gonna emit event cause modifiying the state (good practice)...
        emit CollateralRedeemed(_from,_to,_tokenColleteralAddress,_amountColleteral);
        
        bool success=IERC20(_tokenColleteralAddress).transfer(_to,_amountColleteral);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
    }



    function _getAccountInformation(address user) private 
                                                  view
                                                  returns(uint256 totalDSCMinted,uint256 colleteralValueInUsd){
        totalDSCMinted=s_DSCMinted[user];
        colleteralValueInUsd=getAccountCollateralValue(user);
    }


    function _healthFactor(address user)private view returns(uint256){
        // 1. total minted DSC
        // 2. total colleteral value
        if(s_DSCMinted[user]==0){
            return 1e18;
        }
        (uint256 totalDscminted,uint256 colleteralValueInUsd)=_getAccountInformation(user);
        /* return (colleteralValueInUsd/totalDscminted); */
        // $1000 dolar değerinde ether ve 100 DSC token
        // $1000 * 50=50000/100=500/100=> 1 den büyük olacaktır.
        
        //$150 ETH /100 DSC=1.5
        //150 *50=7500/100=75/100<1
        return _calculateHealthFactor(totalDscminted,colleteralValueInUsd);
    }

    function _calculateHealthFactor(uint256 _totalDscminted,uint256 _colleteralValueInUsd)        
       internal
        pure
        returns (uint256){
            if(_totalDscminted==0) return type(uint256).max;
            uint256 collateralAdjustedForThreshold = (_colleteralValueInUsd * LIQUIDATION_THRESHOLD) / 100;
            return (collateralAdjustedForThreshold * 1e18) / _totalDscminted;
        }
             // 1. Check health factor(do they enough colleteral)
             // 2. Revert if they dont have good health factor
    function _revertIfHealthFactorIsBroken(address user) internal  view{

        uint256 userHealthFactor=_healthFactor(user);
        
        if(userHealthFactor<MIN_HEALTH_FACTOR){
          revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }

    }
    //! //////////////////////////////////////////////////// 
    //! ////////// Public & external view & pure Functions//
    //! ///////////////////////////////////////////////////

    function getAccountCollateralValue(address user) public view returns(uint256 totalColleteralValueInUsd){
        for(uint256 i=0;i<s_colleteralTokens.length;i++){
           address token=s_colleteralTokens[i];
           uint256 amount=s_colleteralDeposited[user][token];
           totalColleteralValueInUsd+=getUsdValue(token,amount);
        }
        return totalColleteralValueInUsd;
    }

    function getTokenAmountFromUsd(address _tokenAddress,uint256 _usdAmountinWei)public view returns(uint256){
        address priceFeedAddr=s_priceFeeds[_tokenAddress];
        (/* uint80 roundId */, 
        int256 price, 
        /* uint256 startedAt */, 
        /* uint256 updatedAt */, 
        /* uint80 answeredInRound */)=AggregatorV3Interface(priceFeedAddr).staleCheckLatestRoundData();
        //(10e18*1e18)/($2000e8*1e10)
        //5,000,000,000,000,0000 -> 0.005 e18...
        return(_usdAmountinWei*PRECISION)/(uint256(price)*ADDITIONAL_FEED_PRECISION);   
    }

    function getUsdValue(address _token,uint256 _amount) public view returns(uint256){
    AggregatorV3Interface priceFeed= AggregatorV3Interface(s_priceFeeds[_token]);
    (,int256 price,,,)=priceFeed.staleCheckLatestRoundData();
    // 1 Eth= $1000;
    // The return value of CL will be 1000*1e8;
     return  (((uint256(price)*ADDITIONAL_FEED_PRECISION)*_amount)/PRECISION);               
    }

        function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

     function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }


    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_colleteralDeposited[user][token];
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_colleteralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_decentralizedStableCoin);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}