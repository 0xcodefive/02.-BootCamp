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

    function burn (address _from, uint256 _amount) external {
        _burn(_from, _amount);
    }

    function setNewMinter (address _newMinter) public onlyOwner {
        minter = _newMinter;
    }
}