namespace Common.Logging.NLogNetStandard
{
    using Common.Logging.NLog;

    using NUnit.Framework;

    [TestFixture]
    public class DummyTest
    {
        [Test]
        public void TestThatPasses()
        {
            NLogGlobalVariablesContext myVar = new NLogGlobalVariablesContext();
            myVar.Clear();
            Assert.IsTrue(true);
        }
    }
}
