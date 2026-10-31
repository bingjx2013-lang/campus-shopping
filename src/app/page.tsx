export default function HomePage() {
  return (
    <main className="page">
      <header className="topbar">
        <div className="brand">明德校园购</div>
        <span className="tag">校内服务</span>
      </header>
      <section className="hero">
        <p className="eyebrow">MINGDE CAMPUS SHOPPING</p>
        <h1>校园好物，<br />安心选购</h1>
        <p className="intro">面向明德中英文学校的校内购物平台。商品、订单与校园钱包服务正在建设中。</p>
        <div className="notice">开发预览版 · 暂不开放真实交易</div>
      </section>
      <section className="tiles" aria-label="平台功能预览">
        <article><span>01</span><h2>精选商品</h2><p>浏览校内商家商品</p></article>
        <article><span>02</span><h2>订单管理</h2><p>查看订单与配送进度</p></article>
        <article><span>03</span><h2>校园钱包</h2><p>安全查看余额与流水</p></article>
      </section>
      <footer>明德校园购 · 开发预览</footer>
    </main>
  );
}
