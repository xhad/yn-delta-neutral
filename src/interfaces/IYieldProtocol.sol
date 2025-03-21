// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IYieldProtocol
 * @notice Interface for yield protocols that generate returns on stablecoins
 */
interface IYieldProtocol {
    /**
     * @notice Deposit stablecoins to the yield protocol
     * @param asset Address of the stablecoin asset
     * @param amount Amount to deposit
     * @return sharesMinted Amount of shares minted for the deposit
     */
    function deposit(address asset, uint256 amount) external returns (uint256 sharesMinted);
    
    /**
     * @notice Withdraw stablecoins from the yield protocol
     * @param asset Address of the stablecoin asset
     * @param shares Amount of shares to redeem
     * @return amountWithdrawn Amount of stablecoins withdrawn
     */
    function withdraw(address asset, uint256 shares) external returns (uint256 amountWithdrawn);
    
    /**
     * @notice Get the current balance of stablecoins in the protocol
     * @param asset Address of the stablecoin asset
     * @param account Address of the account
     * @return balance Current balance
     * @return shares Current shares
     */
    function getBalance(address asset, address account) external view returns (uint256 balance, uint256 shares);
    
    /**
     * @notice Get the current APR for a stablecoin in the protocol
     * @param asset Address of the stablecoin asset
     * @return apr Current APR in basis points (1% = 100 basis points)
     */
    function getCurrentAPR(address asset) external view returns (uint256 apr);
    
    /**
     * @notice Get the total value locked in the protocol for a stablecoin
     * @param asset Address of the stablecoin asset
     * @return tvl Total value locked
     */
    function getTVL(address asset) external view returns (uint256 tvl);
} 