module Main where

import Text.XML.Expat.Tree
import qualified Data.ByteString as B
import Data.ByteString.Internal (c2w, w2c)
import qualified Data.ByteString.Lazy as L
import Control.Monad

infiniteDoc = "<?xml version=\"1.0\"?><infinite>"++body 1
    where
        body i | i == 5000 = "</bad-xml>" ++ body (i+1)
        body i = "\n  <item idx=\"" ++ show i ++ "\"/>"++body (i+1)

toBL :: String -> L.ByteString
toBL = L.fromChunks . chunkify
  where
    chunkify [] = []
    chunkify str =
        let (start, rem) = splitAt 1024 str
        in  (B.pack $ map c2w start):chunkify rem

infiniteBL = toBL infiniteDoc

-- This test passes if it raises an exception when it gets bad XML.

main = do
    print $ (parseTreeThrowing Nothing infiniteBL :: UNode B.ByteString)

