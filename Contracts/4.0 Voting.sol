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

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract Voting {
    enum Types {
        simple,
        bySBT
    }

    struct Option {
        uint voteCount;
        string name;
    }
    
    struct Session {
        bool isActive;
        uint minQuorum;
        uint allVoteCount;
        address owner;
        string topic;
        Types typeOf;
        address addrForVote;
    }

    mapping(uint256 => Option[]) public options;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => mapping(uint256 => bool)) public hasVotedBySBT;
    mapping(uint256 => mapping(address => uint)) public votes;
    mapping(uint256 => mapping(uint256 => uint)) public votesBySBT;
    
    Session[] public sessions;
    address public admin;
    
    event NewSessionCreated(uint indexed sessionId, Types typeOf, string topic, string[] optionNames);
    event NewVoteCasted(uint indexed sessionId, uint indexed optionIndex, address indexed voter);
    event MinQuorumSet(uint indexed sessionId, uint minQuorum);
    event SessionClosed(uint indexed sessionId, string topic);
    
    constructor() {
        admin = msg.sender;
    }
    
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this function");
        _;
    }
    
    modifier onlySessionOwner(uint sessionId) {
        require(msg.sender == sessions[sessionId].owner, "Only session owner can call this function");
        _;
    }
    
    function createNewSessionSimple(address _owner, string memory _topic, string[] memory _optionNames) public onlyAdmin returns (uint) {
        uint number = createNewSession(_owner, address(this), _topic, _optionNames);
        emit NewSessionCreated(sessions.length - 1, Types.simple, _topic, _optionNames);
        return number;
    }

    function createNewSessionBySBT(address _owner, address addrSBT, string memory _topic, string[] memory _optionNames) public onlyAdmin returns (uint) {
        require(IERC721(contractAddress).supportsInterface(0x80ac58cd), "Specified address SBT is not valid");
        uint number = createNewSession(_owner, addrSBT, _topic, _optionNames);
        emit NewSessionCreated(sessions.length - 1, Types.bySBT, _topic, _optionNames);
        return number;
    }

    function createNewSession(address _owner, address _addrForVote, string memory _topic, string[] memory _optionNames) private returns (uint){
        for (uint i = 0; i < _optionNames.length; i++) {
            options[sessions.length].push(Option({name: _optionNames[i], voteCount: 0}));
        }
        
        Session memory newSession = Session({
            owner: _owner,
            topic: _topic,
            isActive: true,
            minQuorum: 0,
            allVoteCount: 0,
            typeOf: 0,            
            addrForVote: _addrForVote
        });
        sessions.push(newSession);
        return sessions.length - 1;
    }
    
    function castVote(uint sessionId, uint optionIndex) public {
        require(sessions.length > sessionId, "Invalid session id");
        require(sessions[sessionId].isActive, "This session is closed");        
        require(optionIndex < options[sessionId].length, "Invalid option index");
        
        if (sessions[sessionId].typeOf == Types.bySBT) {
            require(IERC721(sessions[sessionId].addrForVote).balanceOf(msg.sender) > 0, "No voting rights");            
            uint256 tokenIndex = IERC721(sessions[sessionId].addrForVote).tokenOfOwnerByIndex(msg.sender, 0);
            require(!hasVotedBySBT[sessionId][tokenIndex], "Your token have already voted");
            hasVotedBySBT[sessionId][tokenIndex] = true;
            votesBySBT[sessionId][tokenIndex] = optionIndex;
        } else {
            require(!hasVoted[sessionId][msg.sender], "You have already voted");
            hasVoted[sessionId][msg.sender] = true;
            votes[sessionId][msg.sender] = optionIndex;
        }  
        
        options[sessionId][optionIndex].voteCount++;
        sessions[sessionId].allVoteCount++;
        
        emit NewVoteCasted(sessionId, optionIndex, msg.sender);
    }
    
    function getVoteCount(uint sessionId, uint optionIndex) public view returns (uint) {
        require(sessions.length > sessionId, "Invalid session id");
        require(optionIndex < options[sessionId].length, "Invalid option index");
        
        return options[sessionId][optionIndex].voteCount;
    }
    
    function getSessionsCount() public view returns (uint) {
        return sessions.length;
    }
    
    function getSessionResult(uint sessionId) public view returns (Option[] memory) {
        require(sessions.length > sessionId, "Invalid session id");
        require(!sessions[sessionId].isActive, "This session is still active");        
        return options[sessionId];
    }
    
    function setMinQuorum(uint sessionId, uint _minQuorum) public onlySessionOwner(sessionId) {
        require(sessions[sessionId].isActive, "This session is not active");
        sessions[sessionId].minQuorum = _minQuorum;
        emit MinQuorumSet(sessionId, _minQuorum);
    }
    
    function closeSession(uint sessionId) public onlySessionOwner(sessionId) {
        require(sessions[sessionId].isActive, "This session is not active");
        require(sessions[sessionId].allVoteCount >= sessions[sessionId].minQuorum, "Cannot close a session that has not reached a quorum");
        sessions[sessionId].isActive = false;
        emit SessionClosed(sessionId, sessions[sessionId].topic);
    }

    function transferSessionOwner(uint sessionId, address newOwner) public onlySessionOwner(sessionId) {
        require(sessions[sessionId].isActive, "This session is not active");
        sessions[sessionId].owner = newOwner;
    }

    function transferSessionOwnerByAdmin(uint sessionId, address newOwner) public onlyAdmin {
        require(sessions[sessionId].isActive, "This session is not active");
        sessions[sessionId].owner = newOwner;
    }

    function changeAdmin(address newAdmin) public onlyAdmin {
        admin = newAdmin;
    }
}