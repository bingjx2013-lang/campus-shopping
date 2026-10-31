export default function ProductsPage() {
  return (
    <main className="page">
      <header className="topbar">
        <a className="brand" href="/">明德校园购</a>
        <span className="tag">商品</span>
      </header>
      <section className="hero">
        <p className="eyebrow">CAMPUS MARKET</p>
        <h1>精选商品</h1>
        <p className="intro">商品目录正在接入中。当前预览环境尚未连接商品数据库，因此不会显示虚构商品或库存。</p>
        <div className="notice">开发预览版 · 暂无可购买商品</div>
      </section>
      <p style={{ color: "#788397", fontSize: 13, marginTop: 20 }}>
        商品上架后，将在此展示商品详情、规格、价格及实时库存。
      </p>
    </main>
  );
}
