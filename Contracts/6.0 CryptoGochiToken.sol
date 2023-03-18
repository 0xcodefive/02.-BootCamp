// SPDX-License-Identifier: MIT
/************************************************************\
*                                                            *
*      ██████╗ ██╗  ██╗ ██████╗ ██████╗ ██████╗ ███████╗     *
*     ██╔═████╗╚██╗██╔╝██╔════╝██╔═████╗██╔══██╗██╔════╝     *
*     ██║██╔██║ ╚███╔╝ ██║     ██║██╔██║██║  ██║█████╗       *
*     ████╔╝██║ ██╔██╗ ██║     ████╔╝██║██║  ██║██╔══╝       *
*     ╚██████╔╝██╔╝ ██╗╚██████╗╚██████╔╝██████╔╝███████╗     *
*      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝     *
*                                                            *
\************************************************************/                                                  

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract CryptoGochiToken is ERC20 {
    using SafeMath for uint256;
    address public owner;
    address public minter;
    uint256 public constant FEE_PERCENT = 5; //0.5%
    event NewMinter (address indexed oldMinter, address indexed newMinter);

    modifier onlyOwner{
        require(msg.sender == owner, "Only owner!");
        _;
    }

    modifier onlyMinter{
        require(msg.sender == owner, "Only owner!");
        _;
    }

    constructor() ERC20("CryptoGochiToken", "GOCHI") {
        owner = msg.sender;
        minter = msg.sender;
        uint256 initialSupply = 10 * 10 ** decimals();
        _mint(owner, initialSupply);
    }

    function mint (address _to, uint256 _amount) external onlyMinter {
        _mint(_to, _amount);
    }

    function _burn(address account, uint256 amount) internal override {
        require(account != address(0), "ERC20: burn from the zero address");

        uint256 feeAmount = calculateFee(amount);
        uint256 transferAmount = amount.sub(feeAmount);

        _beforeTokenTransfer(account, address(0), transferAmount);
        uint256 accountBalance = _balances[account];
        require(accountBalance >= transferAmount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - transferAmount;
            _totalSupply -= transferAmount;
        }
        emit Transfer(account, address(0), transferAmount);
        _afterTokenTransfer(account, address(0), transferAmount);
        
        transferFrom(account, owner, feeAmount);
    }

    function calculateFee(uint256 amount) public pure returns (uint256) {
        return amount.mul(FEE_PERCENT).div(1000);
    }

    function setNewMinter (address _newMinter) public onlyOwner {
        minter = _newMinter;
    }

    function transferOwner(address _newOwner) public onlyOwner {
        owner = _newOwner;
    }
}