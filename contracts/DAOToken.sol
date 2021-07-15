// SPDX-License-Identifier: GPL-2.0+
pragma solidity >=0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


import "./interfaces/external/INonfungiblePositionManager.sol";
import "./interfaces/IDAOToken.sol";

import "./libraries/FullMath.sol";
import "./libraries/MintMath.sol";

/// @title DAO Token Contracts.
contract DAOToken is IDAOToken, ERC20 {
    using FullMath for uint256;
    using MintMath for MintMath.Anchor;
    using SafeERC20 for IERC20;

    address private _owner;
    uint256 private _temporaryAmount;
    
    address public immutable staking;
    uint256 public immutable lpRatio;

    address public quoteTokenAddress;
    uint256 public lpTokenId;
    
    address public constant UNISWAP_V3_POSITIONS = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    uint256 public constant MAX_UINT256 = type(uint256).max;
    uint128 public constant MAX_UINT128 = type(uint128).max;
    
    MintMath.Anchor public anchor;

    mapping (address=>bool) managers;

    modifier onlyOwner() {
        require(_msgSender() == _owner, "ICPDAO: NOT OWNER");
        _;
    }

    modifier onlyOwnerOrManager() {
        require(managers[_msgSender()] || _msgSender() == _owner, "NOT OWNER OR MANAGER");
        _;
    }

    constructor(
        address[] memory _genesisTokenAddressList,
        uint256[] memory _genesisTokenAmountList,
        uint256 _lpRatio,
        address _stakingAddress,
        address _ownerAddress,
        int256[7] memory _miningArgs,
        string memory _erc20Name,
        string memory _erc20Symbol
    ) ERC20(_erc20Name, _erc20Symbol) {
        require(_genesisTokenAddressList.length == _genesisTokenAmountList.length, "ICPDAO: GENESIS ADDRESS LENGTH != AMOUNT LENGTH");
        for (uint256 i = 0; i < _genesisTokenAddressList.length; i++) {
            _mint(_genesisTokenAddressList[i], _genesisTokenAmountList[i]);
        }
        if (totalSupply() > 0) {
            _temporaryAmount = totalSupply().divMul(100, _lpRatio);
        }
        anchor.initialize(_miningArgs, block.timestamp);
        _owner = _ownerAddress;
        staking = _stakingAddress;
        lpRatio = _lpRatio;
    }

    function owner() external view virtual override returns (address) {
        return _owner;
    }

    function addManager(address manager) external override onlyOwner {
        require(manager != address(0), "ICPDAO: MANGAGER IS ZERO");
        managers[manager] = true;
    }

    function removeManager(address manager) external override onlyOwner {
        require(manager != address(0), "ICPDAO: MANAGER IS ZERO");
        managers[manager] = false;
    }

    function createLPPool(
        uint256 _baseTokenAmount,
        address _quoteTokenAddress,
        uint256 _quoteTokenAmount,
        uint24 _fee,
        int24 _tickLower,
        int24 _tickUpper,
        uint160 _sqrtPriceX96,
        uint256 _deadline
    ) external payable override onlyOwnerOrManager {
        require(_baseTokenAmount <= _temporaryAmount, "ICPDAO: NOT ENOUGH TEMPORARYAMOUNT");
        IERC20(address(this)).safeApprove(UNISWAP_V3_POSITIONS, MAX_UINT256);
        IERC20(_quoteTokenAddress).safeApprove(UNISWAP_V3_POSITIONS, MAX_UINT256);
        
        address tokenA = address(this);
        address tokenB = _quoteTokenAddress;
        uint256 tokenAAmount = _baseTokenAmount;
        uint256 tokenBAmount = _quoteTokenAmount;

        if (tokenA > tokenB) {
            (tokenA, tokenB) = (tokenB, tokenA);
            (tokenAAmount, tokenBAmount) = (tokenBAmount, tokenAAmount);
        }
        
        INonfungiblePositionManager(UNISWAP_V3_POSITIONS).createAndInitializePoolIfNecessary(
            tokenA, tokenB, _fee, _sqrtPriceX96);
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: tokenA,
            token1: tokenB,
            fee: _fee,
            tickLower: _tickLower,
            tickUpper: _tickUpper,
            amount0Desired: tokenAAmount,
            amount1Desired: tokenBAmount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: _deadline
        });

        (lpTokenId, , , ) = INonfungiblePositionManager(UNISWAP_V3_POSITIONS).mint{value: address(this).balance}(params);
        
        INonfungiblePositionManager(UNISWAP_V3_POSITIONS).refundETH();
        if (address(this).balance > 0) IERC20(address(this)).safeTransfer(_msgSender(), address(this).balance);
        _temporaryAmount -= _baseTokenAmount;
        quoteTokenAddress = _quoteTokenAddress;
    }

    function updateLPPool(
        uint256 _baseTokenAmount,
        uint256 _deadline
    ) external override onlyOwnerOrManager {
        require(_baseTokenAmount <= _temporaryAmount, "ICPDAO: NOT ENOUGH TEMPORARYAMOUNT");
        require(lpTokenId != 0, "ICPDAO: LP POOL DOES NOT EXIST");
        uint256 amount0Desired;
        uint256 amount1Desired;
        if (address(this) > quoteTokenAddress) {
            amount0Desired = _baseTokenAmount;
        } else {
            amount1Desired = _baseTokenAmount;
        }
        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId: lpTokenId,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: 0,
            amount1Min: 0,
            deadline: _deadline
        });
        INonfungiblePositionManager(UNISWAP_V3_POSITIONS).increaseLiquidity(params);
        if (address(this).balance > 0) IERC20(address(this)).safeTransfer(_msgSender(), address(this).balance);
        _temporaryAmount -= _baseTokenAmount;
    }

    function mint(
        address[] memory _mintTokenAddressList,
        uint256[] memory _mintTokenAmountList,
        uint256 _endTimestamp,
        uint256 _deadline
    ) external override onlyOwnerOrManager {
        require(_mintTokenAddressList.length == _mintTokenAmountList.length, "ICPDAO: MINT ADDRESS LENGTH != AMOUNT LENGTH");
        require(_endTimestamp <= block.timestamp, "ICPDAO: MINT TIMESTAMP > BLOCK TIMESTAMP");
        require(_endTimestamp > anchor.lastTimestamp, "ICPDAO: MINT TIMESTAMP < LAST MINT TIMESTAMP");
        uint256 totalSum = anchor.total(_endTimestamp);
        uint256 lastTotal = totalSupply();
        for (uint256 i = 0; i < _mintTokenAddressList.length; i++) {
            _mint(_mintTokenAddressList[i], _mintTokenAmountList[i]);
        }
        uint256 userAmount = totalSupply() - lastTotal;
        uint256 thisTemporaryAmount = userAmount.divMul(100, lpRatio);
        require(totalSum >= (userAmount + thisTemporaryAmount), "ICPDAO: MINT TOTAL TOKEN < USER AMOUNT");
        if (lpTokenId == 0) {
            _temporaryAmount += thisTemporaryAmount;
        } else {
            this.updateLPPool(thisTemporaryAmount, _deadline);
        }
    }

    function bonusWithdraw() external override {
        require(lpTokenId != 0, "ICPDAO: LP POOL DOES NOT EXIST");
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: lpTokenId,
            recipient: staking,
            amount0Max: MAX_UINT128,
            amount1Max: MAX_UINT128
        });
        INonfungiblePositionManager(UNISWAP_V3_POSITIONS).collect(params);
    }
}