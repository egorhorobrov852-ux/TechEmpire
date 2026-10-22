import React, { useCallback, useEffect, useRef, useState } from 'react';
import './TECHEMPIRECommandCenterV3.css';
import { City3D } from './City3D';
type Biz = {
  id: string;
  name: string;
  icon: string;
  cost: number;
  daily: number;
  desc: string;
};
type Save = {
  cash: number;
  day: number;
  city: string;
  country: string;
  mode: string;
  owned: string[];
  tab: string;
  intro: boolean;
  tutorialDone: boolean;
  lastTick: number;
  timeLeft: number;
};
const businesses: Biz[] = [{
  id: 'coffee',
  name: 'Кофейня «У дома»',
  icon: '☕',
  cost: 85000,
  daily: 6200,
  desc: 'Постоянные клиенты и стабильный ежедневный спрос.'
}, {
  id: 'delivery',
  name: 'Служба доставки',
  icon: '🚚',
  cost: 140000,
  daily: 9800,
  desc: 'Зарабатывай на скорости и удобстве для жителей.'
}, {
  id: 'market',
  name: 'Мини-маркет',
  icon: '🏪',
  cost: 210000,
  daily: 14500,
  desc: 'Товары первой необходимости и поток покупателей.'
}, {
  id: 'studio',
  name: 'IT-студия',
  icon: '💻',
  cost: 300000,
  daily: 18500,
  desc: 'Цифровые услуги для растущего делового района.'
}];
const tabs = ['Главная', 'Город', 'Бизнес', 'Финансы', 'Новости'];
const countries: Record<string, { label: string; currency: string; multiplier: number; tax: number; cities: string[] }> = {
  RU: { label: 'Россия', currency: 'RUB', multiplier: 1, tax: 20, cities: ['Екатеринбург', 'Москва', 'Санкт-Петербург', 'Казань', 'Новосибирск'] },
  US: { label: 'США', currency: 'USD', multiplier: 1.45, tax: 24, cities: ['Нью-Йорк', 'Остин', 'Чикаго', 'Сиэтл', 'Лос-Анджелес'] },
  DE: { label: 'Германия', currency: 'EUR', multiplier: 1.18, tax: 29, cities: ['Берлин', 'Мюнхен', 'Гамбург', 'Франкфурт', 'Кёльн'] }
};
const durations: Record<string, number> = {
  'Реальное время': 86400000,
  'Быстрый день': 7200000,
  'Вручную': 0
};
const money = (n: number) => new Intl.NumberFormat('ru-RU', {
  style: 'currency',
  currency: 'RUB',
  maximumFractionDigits: 0
}).format(n);
const defaultSave: Save = {
  cash: 500000,
  day: 1,
  city: 'Екатеринбург',
  country: 'RU',
  mode: 'Вручную',
  owned: [],
  tab: 'Главная',
  intro: true,
  tutorialDone: false,
  lastTick: Date.now(),
  timeLeft: 7200000
};
function loadSave(): Save {
  try {
    const raw = localStorage.getItem('tech-empire-save-v3');
    if (!raw) return defaultSave;
    const s = {
      ...defaultSave,
      ...JSON.parse(raw)
    } as Save;
    const interval = durations[s.mode] || 0;
    if (interval > 0) {
      const elapsed = Math.max(0, Date.now() - (s.lastTick || Date.now()));
      const before = Math.max(1000, s.timeLeft || interval);
      if (elapsed >= before) {
        const after = elapsed - before;
        const completed = 1 + Math.floor(after / interval);
        const income = businesses.filter(b => s.owned.includes(b.id)).reduce((sum, business) => sum + Math.round(business.daily * (countries[s.country] || countries.RU).multiplier), 0);
        s.cash += completed * income;
        s.day += completed;
        s.timeLeft = interval - after % interval;
      } else {
        s.timeLeft = before - elapsed;
      }
      s.lastTick = Date.now();
    }
    return s;
  } catch {
    return defaultSave;
  }
}
export function TECHEMPIRECommandCenter() {
  const [save, setSave] = useState<Save>(() => loadSave());
  const [tutorial, setTutorial] = useState(false);
  const [tutorialStep, setTutorialStep] = useState(0);
  const [toast, setToast] = useState('');
  const [transition, setTransition] = useState('');
  const [remaining, setRemaining] = useState(save.timeLeft);
  const touchX = useRef<number | null>(null);
  const timerRef = useRef<number | undefined>(undefined);
  const owned = businesses.filter(b => save.owned.includes(b.id));
  const profile = countries[save.country] || countries.RU;
  const money = (n: number) => new Intl.NumberFormat('ru-RU', { style: 'currency', currency: profile.currency, maximumFractionDigits: 0 }).format(n);
  const income = owned.reduce((a, b) => a + Math.round(b.daily * profile.multiplier), 0);
  const valuation = save.cash + owned.reduce((a, b) => a + b.cost, 0);
  const update = (patch: Partial<Save>) => setSave(s => ({
    ...s,
    ...patch
  }));
  const notify = (msg: string) => {
    setToast(msg);
    window.setTimeout(() => setToast(''), 2600);
  };
  useEffect(() => {
    localStorage.setItem('tech-empire-save-v3', JSON.stringify({
      ...save,
      lastTick: Date.now(),
      timeLeft: remaining
    }));
  }, [save, remaining]);
  useEffect(() => {
    if (save.mode === 'Вручную') return;
    timerRef.current = window.setInterval(() => {
      setRemaining(v => {
        if (v <= 1000) {
          setSave(s => ({
            ...s,
            day: s.day + 1,
            cash: s.cash + businesses.filter(b => s.owned.includes(b.id)).reduce((a, b) => a + Math.round(b.daily * (countries[s.country] || countries.RU).multiplier), 0),
            lastTick: Date.now()
          }));
          notify('Новый игровой день! Доход начислен.');
          return durations[save.mode] || 7200000;
        }
        return v - 1000;
      });
    }, 1000);
    return () => {
      if (timerRef.current) window.clearInterval(timerRef.current);
    };
  }, [save.mode]);
  const setTabSmooth = (next: string) => {
    if (next === save.tab) return;
    const a = tabs.indexOf(save.tab),
      b = tabs.indexOf(next);
    setTransition(b >= a ? 'slide-left' : 'slide-right');
    update({
      tab: next
    });
    window.setTimeout(() => setTransition(''), 360);
  };
  const swipeStart = (e: React.TouchEvent) => {
    touchX.current = e.touches[0].clientX;
  };
  const swipeEnd = (e: React.TouchEvent) => {
    if (touchX.current === null) return;
    const dx = e.changedTouches[0].clientX - touchX.current;
    touchX.current = null;
    if (Math.abs(dx) < 65) return;
    const i = tabs.indexOf(save.tab);
    const next = dx < 0 ? Math.min(tabs.length - 1, i + 1) : Math.max(0, i - 1);
    if (next !== i) setTabSmooth(tabs[next]);
  };
  const closeDay = () => {
    update({
      day: save.day + 1,
      cash: save.cash + income,
      lastTick: Date.now(),
      timeLeft: durations[save.mode] || 7200000
    });
    setRemaining(durations[save.mode] || 7200000);
    notify('День завершён. Начислено ' + money(income));
  };
  const buy = (b: Biz) => {
    if (save.owned.includes(b.id)) {
      notify('Этот бизнес уже твой');
      return;
    }
    if (save.cash < Math.round(b.cost * profile.multiplier)) {
      notify('Не хватает капитала');
      return;
    }
    update({
      cash: save.cash - Math.round(b.cost * profile.multiplier),
      owned: [...save.owned, b.id]
    });
    notify('Компания открыта: ' + b.name);
  };
  const startGame = () => {
    update({
      intro: false
    });
    if (!save.tutorialDone) {
      setTutorial(true);
      setTutorialStep(0);
    }
  };
  const finishTutorial = () => {
    setTutorial(false);
    update({
      tutorialDone: true,
      tab: 'Главная'
    });
  };
  const fmtTime = (ms: number) => {
    const sec = Math.max(0, Math.floor(ms / 1000));
    return String(Math.floor(sec / 3600)).padStart(2, '0') + ':' + String(Math.floor(sec % 3600 / 60)).padStart(2, '0') + ':' + String(sec % 60).padStart(2, '0');
  };
  return <div className="te3" onTouchStart={swipeStart} onTouchEnd={swipeEnd}>
 {save.intro && <section className="intro3"><div className="intro3-brand"><span className="brandmark">TE</span><span>TECH EMPIRE <small>СТРОЙ СВОЁ БУДУЩЕЕ</small></span><button onClick={() => update({
          intro: false
        })}>Пропустить ↗</button></div><div className="intro3-city" aria-hidden="true">{Array.from({
          length: 24
        }, (_, i) => <i key={i} style={{
          height: 18 + i * 29 % 67 + '%'
        }} />)}</div><div className="intro3-copy"><small>СИМУЛЯТОР БОЛЬШИХ РЕШЕНИЙ</small><h1>Не просто город.<br /><em>Твоя империя.</em></h1><p>Начни с одной идеи. Построй бизнес. Измени целый город.</p><button className="gold3" onClick={startGame}>Начать игру <span>→</span></button></div><div className="intro3-foot">01 / СОЗДАЙ СВОЮ ИСТОРИЮ <span>РАННИЙ ПРОТОТИП</span></div></section>}
 <aside className="side3"><div className="brand3"><span className="brandmark">TE</span><span><b>TECH EMPIRE</b><small>СТРОЙ СВОЁ БУДУЩЕЕ</small></span></div><div className="profile3"><span className="avatar3">И</span><span><b>Основатель</b><small>День {save.day} · Без аккаунта</small></span><i /></div><small className="nav-title3">ТВОЯ ИМПЕРИЯ</small><nav>{tabs.map((t, i) => <button key={t} className={save.tab === t ? 'active' : ''} onClick={() => setTabSmooth(t)}><span>{['⌂', '▦', '▣', '₽', '◉'][i]}</span>{t}{t === 'Город' && <em>3D</em>}</button>)}</nav><div className="side-bottom3"><label>СТРАНА<select value={save.country} onChange={e => { const country = e.target.value; update({ country, city: countries[country].cities[0] }); }}>{Object.entries(countries).map(([key, c]) => <option key={key} value={key}>{c.label}</option>)}</select></label><label>ТВОЙ ГОРОД<select value={save.city} onChange={e => update({ city: e.target.value })}>{profile.cities.map(c => <option key={c}>{c}</option>)}</select></label><button className="link-account3" onClick={() => notify('Прогресс уже сохраняется на этом устройстве. Онлайн-аккаунт добавим отдельно.')}>＋ <span><b>Сохранение включено</b><small>Аккаунт необязателен</small></span><strong>✓</strong></button></div></aside>
 <main className="main3"><header className="top3"><span>ИМПЕРИЯ <i>/</i> <b>{save.tab}</b></span><span className="market3"><i /> РЫНОК АКТИВЕН</span><button onClick={() => {
          setTutorialStep(0);
          setTutorial(true);
        }}>ⓘ Обучение</button></header>
 <div className={'content3 ' + transition} key={save.tab}>
 <div className="heading3"><div><small>● ДЕНЬ {save.day} · {save.city.toUpperCase()}</small><h1>{({
                'Главная': 'Добро пожаловать, основатель.',
                'Город': 'Твой город. Твои правила.',
                'Бизнес': 'Время расти. Твой следующий шаг.',
                'Финансы': 'Каждый рубль на счету.',
                'Новости': 'Решай первым.'
              } as Record<string, string>)[save.tab]}</h1><p>Простые решения сегодня. Большая империя завтра.</p></div>{save.mode === 'Вручную' ? <button className="gold3" onClick={closeDay}>Завершить день →</button> : <div className="timer3"><small>ДО КОНЦА ДНЯ</small><b>{fmtTime(remaining)}</b><span>{save.mode}</span></div>}</div>
 <div className="stats3"><article><small>КАПИТАЛ</small><b>{money(save.cash)}</b><span>Деньги для новых решений</span></article><article><small>ДОХОД / ДЕНЬ</small><b className="green3">{money(income)}</b><span>От действующих бизнесов</span></article><article><small>СТОИМОСТЬ ИМПЕРИИ</small><b>{money(valuation)}</b><span>Капитал и активы</span></article><article><small>ИГРОВОЙ ДЕНЬ</small><b>№ {save.day}</b><button className="inline3" onClick={() => notify('Изменить темп можно в настройках времени ниже.')}>Сменить темп</button></article></div>
 {save.tab === 'Главная' && <><section className="panel3"><div className="panel-head3"><div><small>ТВОЯ ТОЧКА НА КАРТЕ</small><h2>{save.city} <em>● СИМУЛЯЦИЯ</em></h2><p>Выбери район и найди место для первой компании.</p></div><button className="outline3" onClick={() => setTabSmooth('Город')}>Исследовать город ↗</button></div><div className="city3"><City3D city={save.city} /><span className="pin3 pinA">⌂ <small>ЦЕНТР</small></span><span className="pin3 pinB">✦ <small>ДЕЛОВОЙ РАЙОН</small></span><label>ГОРОДСКАЯ ПАНОРАМА <em>ПРОТОТИП</em></label></div><div className="city-foot3"><span>НАСЕЛЕНИЕ <b>1,54 млн</b></span><span>ДЕЛОВАЯ АКТИВНОСТЬ <b className="green3">Растёт ↗</b></span><span>ТВОИ КОМПАНИИ <b>{owned.length}</b></span></div></section><div className="home-grid3"><section className="panel3"><small className="eyebrow3">ПРОСТОЙ СТАРТ</small><h2>Три шага к своей империи</h2><div className="steps3">{[['01', 'Выбери бизнес', 'Оцени цену и доход.'], ['02', 'Запусти дело', 'Открой компанию в один клик.'], ['03', 'Развивай город', 'Получай доход и расширяйся.']].map(x => <div key={x[0]}><i>{x[0]}</i><b>{x[1]}</b><small>{x[2]}</small></div>)}</div><button className="gold3 full3" onClick={() => setTabSmooth('Бизнес')}>Выбрать первый бизнес →</button></section><section className="panel3 next3"><small className="eyebrow3">СЛЕДУЮЩЕЕ РЕШЕНИЕ</small><div className="next-icon3">✦</div><h2>Открой первую компанию</h2><p>Кофейня, доставка или магазин — каждый вариант меняет экономику.</p><button className="inline3" onClick={() => setTabSmooth('Бизнес')}>Посмотреть варианты →</button></section></div></>}
 {save.tab === 'Город' && <section className="panel3"><div className="panel-head3"><div><small>КАРТА РАЗВИТИЯ</small><h2>{save.city}: город возможностей</h2><p>Экономика выбранной страны: {profile.label}. Налоговая нагрузка модели — {profile.tax}%; значения пока игровые, а не официальная статистика.</p></div><select className="city-picker3" value={save.city} onChange={e => update({ city: e.target.value })}>{profile.cities.map(c => <option key={c}>{c}</option>)}</select></div><div className="city3 large-city3"><City3D city={save.city} /><span className="pin3 pinA">⌂ <small>ЦЕНТР</small></span><span className="pin3 pinB">✦ <small>ДЕЛОВОЙ РАЙОН</small></span><label>ГОРОДСКАЯ ПАНОРАМА <em>ПРОТОТИП</em></label></div><div className="districts3">{[['ЦЕНТР', 'Торговля и услуги', 'Высокий спрос'], ['ДЕЛОВОЙ РАЙОН', 'Офисы и технологии', 'Растущий рынок'], ['ПРОМЗОНА', 'Производство', 'Умеренные затраты'], ['НОВЫЙ РАЙОН', 'Жильё и сервисы', 'Потенциал роста']].map(x => <article key={x[0]}><small>{x[0]}</small><b>{x[1]}</b><span>{x[2]}</span></article>)}</div></section>}
 {save.tab === 'Бизнес' && <><div className="panel-head3 business-title3"><div><small>ВЫБЕРИ СВОЙ ПЕРВЫЙ ШАГ</small><h2>Какой бизнес запустим?</h2><p>{profile.label} · {profile.currency}. Стоимость запуска и доходы зависят от выбранной экономической модели.</p></div><b>КАПИТАЛ<br />{money(save.cash)}</b></div><div className="businesses3">{businesses.map(b => <article key={b.id}><div className="biz-icon3">{b.icon}</div><small>АКТИВ · {b.id.toUpperCase()}</small><h3>{b.name}</h3><p>{b.desc}</p><div className="biz-numbers3"><span>СТАРТ <b>{money(b.cost)}</b></span><span>ДОХОД / ДЕНЬ <b className="green3">{money(b.daily)}</b></span></div><button className="gold3 full3" disabled={save.owned.includes(b.id)} onClick={() => buy(b)}>{save.owned.includes(b.id) ? 'Уже открыто' : 'Открыть бизнес →'}</button></article>)}</div><section className="panel3 portfolio3"><small className="eyebrow3">ТВОЙ ПОРТФЕЛЬ</small><h2>Мои компании ({owned.length})</h2>{owned.length === 0 ? <p>Пока пусто. Выбери компанию выше — это займёт один клик.</p> : owned.map(b => <div className="owned3" key={b.id}><span>{b.icon}</span><b>{b.name}</b><small>Работает</small><strong>{money(b.daily)} / день</strong></div>)}</section></>}
 {save.tab === 'Финансы' && <div className="finance-layout3"><section className="panel3"><small className="eyebrow3">ФИНАНСОВОЕ ПОЛОЖЕНИЕ</small><h2 className="balance3">{money(save.cash)}</h2><p>Доступный капитал</p><div className="bars3">{[32, 45, 38, 56, 47, 65, 59, 73, 66, 83, 76, 95].map((v, i) => <i key={i} style={{
                height: v + '%'
              }} />)}</div><small>Динамика — демонстрационная до подключения полной истории операций.</small></section><section className="panel3"><small className="eyebrow3">ДЕНЕЖНЫЙ ПОТОК</small><h2>За игровой день</h2><div className="ledger3"><span>Доход компаний</span><b>{money(income)}</b></div><div className="ledger3"><span>Активные компании</span><b>{owned.length}</b></div><div className="ledger3"><span>Текущий капитал</span><b>{money(save.cash)}</b></div><p className="hint3">Доход начисляется автоматически по выбранному режиму или при ручном завершении дня.</p>{save.mode === 'Вручную' && <button className="gold3 full3" onClick={closeDay}>Начислить доход →</button>}</section></div>}
 {save.tab === 'Новости' && <section className="panel3"><small className="eyebrow3">СИГНАЛЫ ГОРОДА · ДЕНЬ {save.day}</small><h2>Что происходит в экономике</h2><p>Демонстрационные события. Реальные экономические факторы добавим отдельным модулем.</p>{[['СПРОС', 'Жители чаще выбирают удобные услуги', 'Рассмотри доставку или розничную торговлю.'], ['РАСХОДЫ', 'Аренда влияет на прибыль бизнеса', 'Сравни стартовую стоимость и ежедневный доход.'], ['РАЗВИТИЕ', 'Новые районы открывают возможности', 'Рост города создаёт новые ниши для компаний.']].map(x => <div className="news3" key={x[0]}><span>✦</span><div><small>{x[0]}</small><b>{x[1]}</b><p>{x[2]}</p></div></div>)}</section>}
 <section className="panel3 settings3"><div><small className="eyebrow3">ТЕМП ИГРЫ</small><h2>Выбери, как идёт время</h2><p>Настройка сохраняется на устройстве.</p></div><div className="mode-picks3">{[['Вручную', 'Сам решаешь, когда завершить день'], ['Быстрый день', 'Один игровой день за 2 часа'], ['Реальное время', 'Один игровой день за 24 часа']].map(([m, d]) => <button key={m} className={save.mode === m ? 'chosen' : ''} onClick={() => {
              update({
                mode: m,
                lastTick: Date.now(),
                timeLeft: durations[m] || 7200000
              });
              setRemaining(durations[m] || 7200000);
              notify('Режим времени: ' + m);
            }}><i>{save.mode === m ? '✓' : ''}</i><span><b>{m}</b><small>{d}</small></span></button>)}</div></section>
 <footer className="footer3"><span>TECH EMPIRE · РАННИЙ ПРОТОТИП</span><button onClick={() => {
            setTutorialStep(0);
            setTutorial(true);
          }}>Повторить обучение</button><span>АВТОСОХРАНЕНИЕ ВКЛЮЧЕНО</span></footer>
 </div></main>
 {tutorial && <div className="tutorial-backdrop3"><section className="tutorial-card3"><button className="tutorial-close3" onClick={finishTutorial}>×</button><small>БЫСТРОЕ ОБУЧЕНИЕ · ШАГ {tutorialStep + 1} ИЗ 4</small><div className="tutorial-progress3"><i style={{
            width: (tutorialStep + 1) / 4 * 100 + '%'
          }} /></div><div className="tutorial-symbol3">{['⌂', '▣', '₽', '◷'][tutorialStep]}</div><h2>{['Добро пожаловать в империю', 'Выбери первый бизнес', 'Следи за экономикой', 'Управляй игровым временем'][tutorialStep]}</h2><p>{['Здесь собраны капитал, доход и состояние твоего города. Переключай разделы кнопками или свайпом влево и вправо.', 'Открой раздел «Бизнес», сравни стоимость и доход, затем нажми «Открыть бизнес». Покупка сразу меняет капитал.', 'В разделе «Финансы» смотри доступные деньги и доход. В «Новостях» будут появляться события, влияющие на рынок.', 'Выбери ручной режим или включи ускоренный/реальный таймер. Прогресс автоматически сохраняется на этом устройстве.'][tutorialStep]}</p><div className="tutorial-actions3"><button className="outline3" onClick={finishTutorial}>Пропустить</button><button className="gold3" onClick={() => tutorialStep === 3 ? finishTutorial() : setTutorialStep(s => s + 1)}>{tutorialStep === 3 ? 'Начать игру' : 'Далее →'}</button></div></section></div>}
 {toast && <div className="toast3"><span>✓</span>{toast}</div>}
 </div>;
}