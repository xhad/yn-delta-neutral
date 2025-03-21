// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * @title IYieldToken
 * @notice Interface for yield-bearing tokens (ynETHx, ynBTCx, ynUSDx)
 */
interface IYieldToken is IERC20 {
    /**
     * @notice Deposit the underlying asset to receive yield tokens
     * @param amount Amount of underlying asset to deposit
     * @return mintedAmount Amount of yield tokens minted
     */
    function deposit(uint256 amount) external payable returns (uint256 mintedAmount);
    
    /**
     * @notice Withdraw the underlying asset by burning yield tokens
     * @param amount Amount of yield tokens to burn
     * @return withdrawnAmount Amount of underlying asset withdrawn
     */
    function withdraw(uint256 amount) external returns (uint256 withdrawnAmount);
    
    /**
     * @notice Get the exchange rate between yield token and underlying asset
     * @return rate The current exchange rate (scaled by 1e18)
     */
    function exchangeRate() external view returns (uint256 rate);
    
    /**
     * @notice Get the current APR for this yield token
     * @return apr The current APR in basis points (1% = 100 basis points)
     */
    function currentAPR() external view returns (uint256 apr);
    
    /**
     * @notice Get the address of the underlying asset
     * @return asset Address of the underlying asset
     */
    function underlyingAsset() external view returns (address asset);
} 