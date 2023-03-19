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

pragma solidity ^0.8.19;

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
        require(msg.sender == minter, "Only owner!");
        _;
    }

    constructor() ERC20("CryptoGochiToken", "GCHT") {
        owner = msg.sender;
        minter = msg.sender;
        uint256 initialSupply = 100 * 10 ** decimals();
        _mint(owner, initialSupply);
    }

    function mint(address account, uint256 amount) internal onlyMinter {
        _mint(account, amount);
    }

    function burn(uint256 amount) public {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        uint256 feeAmount = calculateFee(amount);
        uint256 transferAmount = amount.sub(feeAmount);

        _burn(msg.sender, transferAmount);
        _transfer(msg.sender, owner, feeAmount);
    }

    function burnFromOrigin(uint256 amount) public {
        require(balanceOf(tx.origin) >= amount, "Insufficient balance");

        uint256 feeAmount = calculateFee(amount);
        uint256 transferAmount = amount.sub(feeAmount);

        _burn(tx.origin, transferAmount);
        _transfer(tx.origin, owner, feeAmount);
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