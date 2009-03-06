import Text.XML.Expat.IO
import Text.XML.Expat.Tree
import Text.XML.Expat.Format
import Text.XML.Expat.Qualified
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BSL
import Data.ByteString.Internal (c2w, w2c)
import Data.Char
import Data.Maybe
import Control.Monad

toByteString :: String -> BSL.ByteString
toByteString = BSL.pack . map c2w

fromByteString :: BSL.ByteString -> String
fromByteString = map w2c . BSL.unpack

testDoc :: (Show tag, Show text) =>
           (Maybe Encoding -> BSL.ByteString -> Maybe (Node tag text))
        -> (Maybe Encoding -> Node tag text -> BSL.ByteString)
        -> Int
        -> String
        -> IO ()
testDoc parse fmt idx xml = do
  let mTree = parse (Just UTF8) (toByteString xml)
  --when (idx == 1) $ print mTree
  putStr $ "test "++show idx++" - "
  case mTree of
      Just tree -> do
          let out = fromByteString $ fmt (Just UTF8) tree
          --putStrLn out
          if out == xml
              then putStrLn "passed"
              else do
                  putStrLn $ "FAILED: mismatch"
                  putStrLn $ "input="++xml
                  putStrLn $ "output="++out
      Nothing ->
          putStrLn "FAILED: parse failed"

simpleDocs = [
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"++
    "<test xmlns:abc=\"http://blacksapphire.com/abc\"><abc:test1 type=\"expression\">Cat &amp; mouse</abc:test1><test2 type=\"communication\" language=\"Rhyming slang\">Dog &amp; bone</test2></test>",

    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"++
    "<second><test><test1 type=\"expression\">Cat &amp; mouse</test1><test2 type=\"communication\" language=\"Rhyming slang\">Dog &amp; bone</test2></test><test>Rose &amp; Crown</test></second>",

    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<test>Cat &amp; mouse</test>"
  ]

test parse fmt docs = do
    forM_ (zip [1..] docs) $ \(idx, doc) ->
        testDoc parse fmt idx doc

main = do
    testDoc <- readFile "test.xml"
    -- Remove trailing newline
    let testDoc' = reverse . dropWhile (== '\n') . reverse $ testDoc
    let docs = simpleDocs ++ [testDoc']

    putStrLn "String"
    test parseTreeString formatTreeString docs
    putStrLn "ByteString"
    test parseTreeByteString formatTreeByteString docs
    putStrLn "Text"
    test parseTreeText formatTreeText docs
    putStrLn "String/Lazy"
    test (enjust parseTreeStringLazy) formatTreeString docs
    putStrLn "ByteString/Lazy"
    test (enjust parseTreeByteStringLazy) formatTreeByteString docs
    putStrLn "Text/Lazy"
    test (enjust parseTreeTextLazy) formatTreeText docs
    putStrLn "String/Qualified"
    test parseQualifiedTreeString formatQualifiedTreeString docs
    putStrLn "ByteString/Qualified"
    test parseQualifiedTreeByteString formatQualifiedTreeByteString docs
    putStrLn "Text/Qualified"
    test parseQualifiedTreeText formatQualifiedTreeText docs
  where
    enjust f mEnc bs = Just $ f mEnc bs

