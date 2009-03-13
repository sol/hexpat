-- hexpat, a Haskell wrapper for expat
-- Copyright (C) 2008 Evan Martin <martine@danga.com>
-- Copyright (C) 2009 Stephen Blackheath <http://blacksapphire.com/antispam>

-- | Low-level interface to Expat. Unless speed is paramount, this
-- should normally be avoided in favour of the interface provided by "Text-XML-Expat-Tree".
-- Basic usage is:
--
-- (1) Make a new parser: 'newParser'.
--
-- (2) Set up callbacks on the parser: 'setStartElementHandler', etc.
--
-- (3) Feed data into the parser: 'parse' or 'parseChunk'.

module Text.XML.Expat.IO (
  -- ** Parser Setup
  Parser, newParser,

  -- ** Parsing
  parse, parseChunk, Encoding(..), XMLParseError(..),

  -- ** Parser Callbacks
  StartElementHandler, EndElementHandler, CharacterDataHandler,
  setStartElementHandler, setEndElementHandler, setCharacterDataHandler,

  -- ** Lower-level interface
  unsafeParseChunk,
  withHandlers,
  unsafeSetHandlers,
  unsafeReleaseHandlers,
  ExpatHandlers,

  -- ** Helpers
  encodingToString
) where

import Control.Exception (bracket)
import Control.Parallel.Strategies
import Control.Monad
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.Internal as BSI
import Data.IORef
import Foreign
import CForeign


-- |Opaque parser type.
type ParserPtr = Ptr ()
data Parser = Parser
    (ForeignPtr ())
    (IORef CStartElementHandler) 
    (IORef CEndElementHandler) 
    (IORef CCharacterDataHandler)

instance Show Parser where
    showsPrec _ (Parser fp _ _ _) = showsPrec 0 fp

withParser :: Parser -> (ParserPtr -> IO a) -> IO a
withParser (Parser fp _ _ _) = withForeignPtr fp

-- |Encoding types available for the document encoding.
data Encoding = ASCII | UTF8 | UTF16 | ISO88591
encodingToString :: Encoding -> String
encodingToString ASCII    = "US-ASCII"
encodingToString UTF8     = "UTF-8"
encodingToString UTF16    = "UTF-16"
encodingToString ISO88591 = "ISO-8859-1"

withOptEncoding :: Maybe Encoding -> (CString -> IO a) -> IO a
withOptEncoding Nothing    f = f nullPtr
withOptEncoding (Just enc) f = withCString (encodingToString enc) f

parserCreate :: Maybe Encoding -> IO (ParserPtr)
parserCreate a1 =
  withOptEncoding a1 $ \a1' -> 
  parserCreate'_ a1' >>= \res ->
  let {res' = id res} in
  return (res')
foreign import ccall "&XML_ParserFree" parserFree :: FunPtr (ParserPtr -> IO ())

-- |Create a 'Parser'.  The encoding parameter, if provided, overrides the
-- document's encoding declaration.
newParser :: Maybe Encoding -> IO Parser
newParser enc = do
  ptr <- parserCreate enc
  fptr <- newForeignPtr parserFree ptr
  nullStartH <- newIORef nullCStartElementHandler
  nullEndH <- newIORef nullCEndElementHandler
  nullCharH <- newIORef nullCCharacterDataHandler
  return $ Parser fptr nullStartH nullEndH nullCharH

-- ByteString.useAsCStringLen is almost what we need, but C2HS wants a CInt
-- instead of an Int.
withBStringLen :: BS.ByteString -> ((CString, CInt) -> IO a) -> IO a
withBStringLen bs f = do
  BS.useAsCStringLen bs $ \(str, len) -> f (str, fromIntegral len)

unStatus :: CInt -> Bool
unStatus 0 = False
unStatus 1 = True

-- |@parse data@ feeds /lazy/ bytestring data into a parser. It returns Nothing
-- on success, or Just the parse error.
parse :: Parser -> BS.ByteString -> IO (Maybe XMLParseError)
parse parser@(Parser _ _ _ _) bs = withHandlers parser $ do
    ok <- doParseChunk parser bs True
    if ok
        then return Nothing
        else Just `fmap` getError parser

-- |@parseChunk data False@ feeds /strict/ ByteString data into a
-- 'Parser'.  The end of the data is indicated by passing @True@ for the
-- final parameter.   It returns Nothing on success, or Just the parse error.
parseChunk :: Parser
           -> BS.ByteString
           -> Bool
           -> IO (Maybe XMLParseError)
parseChunk parser xml final = withHandlers parser $ unsafeParseChunk parser xml final

-- | This variant of 'parseChunk' must either be called inside 'withHandlers' (safest), or
-- between 'unsafeSetHandlers' and 'unsafeReleaseHandlers', and this
-- will give you better performance than 'parseChunk' if you process multiple chunks inside.
unsafeParseChunk :: Parser
           -> BS.ByteString
           -> Bool
           -> IO (Maybe XMLParseError)
unsafeParseChunk parser xml final = do
    ok <- doParseChunk parser xml final
    if ok
        then return Nothing
        else Just `fmap` getError parser

getError parser = withParser parser $ \p -> do
                code <- xmlGetErrorCode p
                cerr <- xmlErrorString code
                err <- peekCString cerr
                line <- xmlGetCurrentLineNumber p
                col <- xmlGetCurrentColumnNumber p
                return $ XMLParseError err
                    (fromIntegral line) (fromIntegral col)

data ExpatHandlers = ExpatHandlers
    (FunPtr CStartElementHandler)
    (FunPtr CEndElementHandler)
    (FunPtr CCharacterDataHandler)

unsafeSetHandlers :: Parser -> IO ExpatHandlers
unsafeSetHandlers parser@(Parser fp startRef endRef charRef) = do
    cStartH <- mkCStartElementHandler =<< readIORef startRef
    cEndH   <- mkCEndElementHandler =<< readIORef endRef
    cCharH  <- mkCCharacterDataHandler =<< readIORef charRef
    withParser parser $ \p -> do
        xmlSetstartelementhandler  p cStartH
        xmlSetendelementhandler    p cEndH
        xmlSetcharacterdatahandler p cCharH
    return $ ExpatHandlers cStartH cEndH cCharH

unsafeReleaseHandlers :: ExpatHandlers -> IO ()
unsafeReleaseHandlers (ExpatHandlers cStartH cEndH cCharH) = do
    freeHaskellFunPtr cStartH
    freeHaskellFunPtr cEndH
    freeHaskellFunPtr cCharH

-- | 'unsafeParseChunk' is required to be called inside @withHandlers@.
-- Safer than using 'unsafeSetHandlers' / 'unsafeReleaseHandlers'.
withHandlers :: Parser
             -> IO a  -- ^ Computation where unsafeParseChunk may be used
             -> IO a
withHandlers parser code = do
    bracket
        (unsafeSetHandlers parser)
        unsafeReleaseHandlers
        (\_ -> code)

-- |Obtain C value from Haskell 'Bool'.
--
cFromBool :: Num a => Bool -> a
cFromBool  = fromBool

doParseChunk :: Parser -> BS.ByteString -> Bool -> IO (Bool)
doParseChunk a1 a2 a3 =
  withParser a1 $ \a1' -> 
  withBStringLen a2 $ \(a2'1, a2'2) -> 
  let {a3' = cFromBool a3} in 
  doParseChunk'_ a1' a2'1  a2'2 a3' >>= \res ->
  let {res' = unStatus res} in
  return (res')

-- | Parse error, consisting of message text, line number, and column number
data XMLParseError = XMLParseError String Integer Integer deriving (Eq, Show)

instance NFData XMLParseError where
    rnf (XMLParseError msg lin col) = rnf (msg, lin, col)

-- |The type of the \"element started\" callback.  The first parameter is
-- the element name; the second are the (attribute, value) pairs. Return True
-- to continue parsing as normal, or False to terminate the parse.
type StartElementHandler  = CString -> [(CString, CString)] -> IO Bool
-- |The type of the \"element ended\" callback.  The parameter is
-- the element name. Return True to continue parsing as normal, or False to
-- terminate the parse.
type EndElementHandler    = CString -> IO Bool
-- |The type of the \"character data\" callback.  The parameter is
-- the character data processed.  This callback may be called more than once
-- while processing a single conceptual block of text. Return True to continue
-- parsing as normal, or False to terminate the parse.
type CharacterDataHandler = CStringLen -> IO Bool

type CStartElementHandler = Ptr () -> CString -> Ptr CString -> IO ()
nullCStartElementHandler _ _ _ = return ()

foreign import ccall unsafe "expat.h XML_GetErrorCode" xmlGetErrorCode
    :: ParserPtr -> IO CInt
foreign import ccall unsafe "expat.h XML_GetCurrentLineNumber" xmlGetCurrentLineNumber
    :: ParserPtr -> IO CUInt  -- to do: Get 64-bit value if supported (how?)
foreign import ccall unsafe "expat.h XML_GetCurrentColumnNumber" xmlGetCurrentColumnNumber
    :: ParserPtr -> IO CUInt  -- to do: Get 64-bit value if supported (how?)
foreign import ccall unsafe "expat.h XML_ErrorString" xmlErrorString
    :: CInt -> IO CString
foreign import ccall unsafe "expat.h XML_StopParser" xmlStopParser
    :: ParserPtr -> CInt -> IO ()

foreign import ccall safe "wrapper"
  mkCStartElementHandler :: CStartElementHandler
                         -> IO (FunPtr CStartElementHandler)

wrapStartElementHandler :: Parser -> StartElementHandler -> CStartElementHandler
wrapStartElementHandler parser@(Parser _ _ _ _) handler = h
  where
    h ptr cname cattrs = do
        cattrlist <- peekArray0 nullPtr cattrs
        stillRunning <- handler cname (pairwise cattrlist)
        unless stillRunning $
            withParser parser $ \p -> xmlStopParser p 0 

-- |Attach a StartElementHandler to a Parser.
setStartElementHandler :: Parser -> StartElementHandler -> IO ()
setStartElementHandler parser@(Parser _ startRef _ _) handler =
    withParser parser $ \p -> do
        writeIORef startRef $ wrapStartElementHandler parser handler

type CEndElementHandler = Ptr () -> CString -> IO ()
nullCEndElementHandler _ _ = return ()

foreign import ccall safe "wrapper"
  mkCEndElementHandler :: CEndElementHandler
                       -> IO (FunPtr CEndElementHandler)
wrapEndElementHandler :: Parser -> EndElementHandler -> CEndElementHandler
wrapEndElementHandler parser@(Parser _ _ _ _) handler = h
  where
    h ptr cname = do
        stillRunning <- handler cname
        unless stillRunning $
            withParser parser $ \p -> xmlStopParser p 0 

-- |Attach an EndElementHandler to a Parser.
setEndElementHandler :: Parser -> EndElementHandler -> IO ()
setEndElementHandler parser@(Parser _ _ endRef _) handler =
    withParser parser $ \p -> do
        writeIORef endRef $ wrapEndElementHandler parser handler

type CCharacterDataHandler = Ptr () -> CString -> CInt -> IO ()
nullCCharacterDataHandler _ _ _ = return ()

foreign import ccall safe "wrapper"
  mkCCharacterDataHandler :: CCharacterDataHandler
                          -> IO (FunPtr CCharacterDataHandler)
wrapCharacterDataHandler :: Parser -> CharacterDataHandler -> CCharacterDataHandler
wrapCharacterDataHandler parser@(Parser _ _ _ _) handler = h
  where
    h ptr cdata len = do
        stillRunning <- handler (cdata, fromIntegral len)
        unless stillRunning $
            withParser parser $ \p -> xmlStopParser p 0 

-- | Attach an CharacterDataHandler to a Parser.
setCharacterDataHandler :: Parser -> CharacterDataHandler -> IO ()
setCharacterDataHandler parser@(Parser _ _ _ charRef) handler =
    withParser parser $ \p -> do
        writeIORef charRef $ wrapCharacterDataHandler parser handler

pairwise (x1:x2:xs) = (x1,x2) : pairwise xs
pairwise []         = []


foreign import ccall unsafe "Text/XML/Expat/IO.chs.h XML_ParserCreate"
  parserCreate'_ :: ((Ptr CChar) -> (IO (Ptr ())))

foreign import ccall unsafe "Text/XML/Expat/IO.chs.h XML_SetStartElementHandler"
  xmlSetstartelementhandler :: ((Ptr ()) -> ((FunPtr ((Ptr ()) -> ((Ptr CChar) -> ((Ptr (Ptr CChar)) -> (IO ()))))) -> (IO ())))

foreign import ccall unsafe "Text/XML/Expat/IO.chs.h XML_SetEndElementHandler"
  xmlSetendelementhandler :: ((Ptr ()) -> ((FunPtr ((Ptr ()) -> ((Ptr CChar) -> (IO ())))) -> (IO ())))

foreign import ccall unsafe "Text/XML/Expat/IO.chs.h XML_SetCharacterDataHandler"
  xmlSetcharacterdatahandler :: ((Ptr ()) -> ((FunPtr ((Ptr ()) -> ((Ptr CChar) -> (CInt -> (IO ()))))) -> (IO ())))

foreign import ccall safe "Text/XML/Expat/IO.chs.h XML_Parse"
  doParseChunk'_ :: ((Ptr ()) -> ((Ptr CChar) -> (CInt -> (CInt -> (IO CInt)))))