// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract ZeroCode is ERC20 {
    using SafeMath for uint256;
    bool airdropIsOver;
    address public owner;
    uint256 public constant FEE_PERCENT = 10;
    uint256 public totalFeesBurned;

    event FeesBurned(uint256 amount);

    modifier onlyOwner{
        require(msg.sender == owner, "Only owner!");
        _;
    }

    constructor() ERC20("ZeroCode", "0xC") {
        owner = msg.sender;
        uint256 initialSupply = 1_000_000 * 10 ** decimals();
        _mint(address(this), initialSupply);
        airdropIsOver = false;
    }

    function airdrop(address[] memory accounts) public onlyOwner {
        require(!airdropIsOver, "Airdrop is over");
        require(balanceOf(address(this)) > 0, "Insufficient balance for airdrop");
        uint256 amount = balanceOf(address(this)).div(accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            _transfer(address(this), accounts[i], amount);
        }
        uint256 balanceToBurn = balanceOf(address(this));
        if (balanceToBurn > 0) {
            totalFeesBurned = totalFeesBurned.add(balanceToBurn);            
            _burn(address(this), balanceToBurn);
            emit FeesBurned(balanceToBurn);
        }
        airdropIsOver = true;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        if (msg.sender == owner) {
            super.transfer(recipient, amount);
            return true;
        }

        uint256 feeAmount = calculateFee(amount);
        uint256 transferAmount = amount.sub(feeAmount);

        super.transfer(recipient, transferAmount);
        totalFeesBurned = totalFeesBurned.add(feeAmount);
        _burn(msg.sender, feeAmount);
        emit FeesBurned(feeAmount);

        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
         if (msg.sender == owner) {
            super.transferFrom(sender, recipient, amount);
            return true;
        }

        uint256 feeAmount = calculateFee(amount);
        uint256 transferAmount = amount.sub(feeAmount);

        super.transferFrom(sender, recipient, transferAmount);
        totalFeesBurned = totalFeesBurned.add(feeAmount);
        _burn(msg.sender, feeAmount);
        emit FeesBurned(feeAmount);

        return true;
    }

    function calculateFee(uint256 amount) public pure returns (uint256) {
        return amount.mul(FEE_PERCENT).div(100);
    }
}