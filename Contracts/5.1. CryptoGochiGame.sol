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

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface ICryptoGochiToken {
    function mint(address account, uint256 amount) external;
    function burnFromOrigin(uint256 amount) external;
}

contract CryptoGochiGame is ReentrancyGuard, VRFConsumerBaseV2, ConfirmedOwner {
    using SafeMath for uint8;
    using SafeMath for uint256;

    ICryptoGochiToken gochiToken;
    address public gochiTokenAddress;
    
    uint256 public limitForFreeMint;
    uint256 public countOfFreeMinted; 
    uint256 public restrictionTimer;
    uint256 public morphMul;
    uint256 public priceToBirth;
    uint256 public priceToSatEd;  
    uint256 private constant st = 100;

    VRFCoordinatorV2Interface COORDINATOR;
    uint16 internal requestConfirmations = 3;
    uint32 internal callbackGasLimit = 300000;
    uint32 internal numWords = 1;
    uint64 internal s_subscriptionId = 2714;
    address internal constant vrfCoordinator = 0x6A2AAd07396B36Fe02a22b33cf443582f682c82f;
    bytes32 internal constant keyHash = 0xd4bb89654db74673a187bd804519e65e3f71a52bc55f11da7601a13dcf505314;

    struct Gochi {
        uint8 level;
        uint8 epoch;
        uint256 feeded;
        uint256 satisfaction;
        uint256 education;
        uint256 restrictionOnFeeded;
        uint256 restrictionOnSatisfaction;
        uint256 restrictionOnEducation;
        uint256 restrictionOnSleep;
        address owner;
        address nanny;
    }
    Gochi[] public gochies;

    uint256 public randomWord;
    mapping(address => bool) public hasFreeGochi;
    mapping(address => uint256) public gochiCountFromAddress;
    mapping(uint256 => uint256) private commitments;

    event NewGochiWasBorn(address indexed owner, uint256 index);
    event GochiHasGrownUp(address indexed owner, uint256 index);

    modifier onlyGochiOwner(uint256 index) {
        require(msg.sender == gochies[index].owner, "Only Gochi owner can call this function");
        _;
    }

    modifier onlyGochiNanny(uint256 index) {
        require(msg.sender == gochies[index].nanny || msg.sender == gochies[index].owner, "Only Gochi owner and nanny can call this function");
        _;
    }

    constructor(address _gochiTokenAddress)
    VRFConsumerBaseV2(0x6A2AAd07396B36Fe02a22b33cf443582f682c82f)
    ConfirmedOwner(msg.sender)
    payable {
        COORDINATOR = VRFCoordinatorV2Interface(
            0x6A2AAd07396B36Fe02a22b33cf443582f682c82f
        );
        restrictionTimer = 60; // 60 sec
        morphMul = 10;
        priceToBirth = 10 * 10**18;
        priceToSatEd = 10**18;
        limitForFreeMint = 10;
        gochiTokenAddress = _gochiTokenAddress;
        gochiToken = ICryptoGochiToken(gochiTokenAddress);
        freeBirthGochi(msg.sender);
    }

    function setRestrictionTimer (uint256 _timer) public onlyOwner {
        restrictionTimer = _timer;
    }

    function setGchiTokenAddress (address _newAddress) public onlyOwner {
        gochiTokenAddress = _newAddress;
        gochiToken = ICryptoGochiToken(gochiTokenAddress);
    }

    function setPriceToBirth (uint256 _newPrice) public onlyOwner {
        priceToBirth = _newPrice;
    }

    function setPriceToSatEd (uint256 _newPrice) public onlyOwner {
        priceToSatEd = _newPrice;
    }
    
    function setLimitForFreeMint (uint32 _newLimit) public onlyOwner {
        limitForFreeMint = _newLimit;
    }

    function freeBirthGochi(address _to) public {
        require(countOfFreeMinted < limitForFreeMint && !hasFreeGochi[_to], "Free birth is not available for you");
        countOfFreeMinted++;
        _birthGochi(_to);
    }

    function birthGochi(address _to) public {
        gochiToken.burnFromOrigin(priceToBirth);
        _birthGochi(_to);
    }

    function _birthGochi(address _to) private {
        gochies.push(Gochi({
            level: 0,
            epoch: 0,
            feeded: 70,
            satisfaction: 70,
            education: 70,
            restrictionOnFeeded: block.timestamp,
            restrictionOnSatisfaction: block.timestamp,
            restrictionOnEducation: block.timestamp,
            restrictionOnSleep: block.timestamp,
            owner: _to,
            nanny: _to
        }));
        gochiCountFromAddress[_to]++;
        emit NewGochiWasBorn(_to, gochies.length - 1);
    }

    function setNannyForGochi(address _to, uint256 _index) public onlyGochiOwner(_index) {
        gochies[_index].nanny = _to;
    }

    function getGochiesByOwner(address _owner) public view returns(Gochi[] memory) {
        uint256 count = gochiCountFromAddress[_owner];
        Gochi[] memory thisGochies = new Gochi[](count);
        count = 0;
        for (uint256 i = 0; i < gochies.length; i++){
            if (gochies[i].owner == _owner){
                thisGochies[count] = gochies[i];
                count++;
            }
            if (thisGochies.length == count) {
                return thisGochies;
            }
        }
        return thisGochies;
    }

    function transferGochiOwner(address _to, uint256 _index) public onlyGochiOwner(_index) {
        gochiCountFromAddress[gochies[_index].owner]--;
        gochies[_index].owner = _to;
        gochiCountFromAddress[_to]++;
    }

    function getGochiFeededByPercent(uint256 _index) public view returns(uint256){
        uint256 max = gochies[_index].level.mul(10).add(st);
        uint256 ths = _getGochiFeeded(_index);
        return max > ths ? ths.mul(100).div(max) : 100;
    }

    function _getGochiFeeded(uint256 _index) private view returns(uint256){
        uint256 proto = gochies[_index].feeded;
        uint256 minus = block.timestamp > gochies[_index].restrictionOnFeeded ? 
            block.timestamp.sub(gochies[_index].restrictionOnFeeded).div(restrictionTimer) : 0;
        return proto > minus ? proto.sub(minus) : 0;
    }

    function feedGochi(uint256 _index) public nonReentrant onlyGochiNanny(_index) {
        require(gochies[_index].restrictionOnSleep <= block.timestamp, "Gochi is sleeping");
        require(gochies[_index].restrictionOnFeeded <= block.timestamp, "Gochi is very well fed");
        uint256 max = gochies[_index].level.mul(10).add(st);
        uint256 ths = _getGochiFeeded(_index).add(10);
        gochies[_index].feeded = ths < max ? ths : max;
        gochies[_index].restrictionOnFeeded = block.timestamp.add(restrictionTimer);
    }

    function getGochiSatisfactionByPercent(uint256 _index) public view returns(uint256){
        uint256 max = gochies[_index].level.mul(10).add(st);
        uint256 ths = _getGochiSatisfaction(_index);
        return max > ths ? ths.mul(100).div(max) : 100;
    }

    function _getGochiSatisfaction(uint256 _index) private view returns(uint256){
        uint256 proto = gochies[_index].satisfaction;
        uint256 minus = block.timestamp > gochies[_index].restrictionOnSatisfaction ? 
            block.timestamp.sub(gochies[_index].restrictionOnSatisfaction).div(restrictionTimer) : 0;
        return proto > minus ? proto.sub(minus) : 0;
    }

    function satisfyGochi(uint256 _index) public nonReentrant onlyGochiNanny(_index) {
        require(gochies[_index].restrictionOnSleep <= block.timestamp, "Gochi is sleeping");
        require(gochies[_index].restrictionOnSatisfaction <= block.timestamp, "Gochi is very well satisfied");
        gochiToken.burnFromOrigin(priceToSatEd);
        uint256 max = gochies[_index].level.mul(10).add(st);
        uint256 ths = _getGochiSatisfaction(_index).add(10);
        gochies[_index].satisfaction = ths < max ? ths : max;
        gochies[_index].restrictionOnSatisfaction = block.timestamp.add(restrictionTimer);
    }

    function getGochiEducationByPercent(uint256 _index) public view returns(uint256){
        uint256 max = gochies[_index].level.mul(10).add(st);
        uint256 ths = _getGochiEducation(_index);
        return max > ths ? ths.mul(100).div(max) : 100;
    }

    function _getGochiEducation(uint256 _index) private view returns(uint256){
        uint256 proto = gochies[_index].education;
        uint256 minus = block.timestamp > gochies[_index].restrictionOnEducation ? 
            block.timestamp.sub(gochies[_index].restrictionOnEducation).div(restrictionTimer) : 0;
        return proto > minus ? proto.sub(minus) : 0;
    }

    function educateGochi(uint256 _index) public nonReentrant onlyGochiNanny(_index) {
        require(gochies[_index].restrictionOnSleep <= block.timestamp, "Gochi is sleeping");
        require(gochies[_index].restrictionOnEducation <= block.timestamp, "Gochi is very well educated");
        gochiToken.burnFromOrigin(priceToSatEd);
        uint256 max = gochies[_index].level.mul(10).add(st);
        uint256 ths = _getGochiEducation(_index).add(10);
        gochies[_index].education = ths < max ? ths : max;
        gochies[_index].restrictionOnEducation = block.timestamp.add(restrictionTimer);
    }

    function gochiMorph(uint256 _index) public nonReentrant onlyGochiNanny(_index) {
        require(_getGochiFeeded(_index) >= 85, "Not fed enough, need more then 85%");
        gochies[_index].epoch += 1;
        gochies[_index].feeded /= 2;
        gochies[_index].satisfaction /= 2;
        gochies[_index].education /= 2;
        gochies[_index].restrictionOnSleep = restrictionTimer.mul(5).add(block.timestamp);
        
        uint256 requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        commitments[requestId] = _index;
    }

    // Callback Randomize
    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        randomWord = _randomWords[0];
        uint256 _index = commitments[_requestId];
        uint256 _doubt = randomWord % 10 + gochies[_index].epoch;
        bool _isReadyToGrownUp = randomWord % 5 == 0;
        if (_isReadyToGrownUp 
         && _doubt >= uint256(gochies[_index].level).add(20) 
         && _getGochiSatisfaction(_index) >= 85 
         && _getGochiEducation(_index) >= 85) {
            gochies[_index].epoch = 0;
            gochies[_index].level += 1;
            emit GochiHasGrownUp(gochies[_index].owner, _index);
        } else {
            gochiToken.mint(gochies[_index].owner, (2**(uint256(gochies[_index].level) + randomWord % 5)).mul(10**17));
        }
    }

    function setRequestRandomWordsrOptions(
        uint16 _requestConfirmations, 
        uint32 _callbackGasLimit, 
        uint32 _numWords,
        uint64 _s_subscriptionId) public onlyOwner {
            requestConfirmations = _requestConfirmations;   
            callbackGasLimit = _callbackGasLimit;
            numWords = _numWords;
            s_subscriptionId = _s_subscriptionId;
    }

    function withdraw() public onlyOwner nonReentrant {
        (bool success, ) = (msg.sender).call{value: address(this).balance}("");
        require(success, "withdraw failed");
    }

    function withdrawTokens(address _token) public onlyOwner nonReentrant {
        IERC20Metadata token = IERC20Metadata(_token);
        uint256 balance = token.balanceOf(address(this));
        token.transfer(msg.sender, balance);
    }
}